// @ts-check
// import '@endo/init/legacy.js';
import './lockdown.js';

import process from 'process';
import express from 'express';
import https from 'https';
import tmp from 'tmp';
import { $, fetch, fs, sleep } from 'zx';

import { makeSubscriptionKit } from '@agoric/notifier';

const { details: X } = globalThis.assert;

const BASE_AMOUNT = "25000000";
const CLIENT_AMOUNT = process.env.CLIENT_AMOUNT;
const DELEGATE_AMOUNT = process.env.DELEGATE_AMOUNT;

const COMMANDS = {
  "SEND_BLD/IBC": "send_bld_ibc",
  "SEND_AND_PROVISION_IST": "send_ist_and_provision",
  "FUND_PROV_POOL": "fund_provision_pool",
  "CUSTOM_DENOMS_LIST": "custom_denoms_list",
};


const PROVISIONING_POOL_ADDR = 'agoric1megzytg65cyrgzs6fvzxgrcqvwwl7ugpt62346';
  
const DOCKERTAG = process.env.DOCKERTAG; // Optional.
const DOCKERIMAGE = process.env.DOCKERIMAGE; // Optional.
const FAUCET_KEYNAME =
  process.env.FAUCET_KEYNAME || process.env.WHALE_KEYNAME || 'bootstrap';
const NETNAME = process.env.NETNAME || 'devnet';
const NETDOMAIN = process.env.NETDOMAIN || '.agoric.net';
const AG0_MODE = (process.env.AG0_MODE || 'false') === 'true';
const agBinary = AG0_MODE ? 'ag0' : 'agd';
const podname = process.env.POD_NAME || 'validator-primary';
const INCLUDE_SEED =  process.env.SEED_ENABLE || 'yes';
const NODE_ID = process.env.NODE_ID || 'fb86a0993c694c981a28fa1ebd1fd692f345348b';

const FAKE = process.env.FAKE || process.argv[2] === '--fake';
if (FAKE && false) {
  console.log('FAKE MODE');
  const tmpDir = await new Promise((resolve, reject) => {
    tmp.dir({ prefix: 'faucet', postfix: 'home' }, (err, path) => {
      if (err) {
        return reject(err);
      }
      resolve(path);
    });
  });
  // Create the temporary key.
  console.log(`Creating temporary key`, { tmpDir, FAUCET_KEYNAME });
  await $`${agBinary} --home=${tmpDir} keys --keyring-backend=test add ${FAUCET_KEYNAME}`;
  process.env.AGORIC_HOME = tmpDir;
}

const agoricHome = process.env.AGORIC_HOME;
assert(agoricHome, X`AGORIC_HOME not set`);

const chainId = process.env.CHAIN_ID;
assert(chainId, X`CHAIN_ID not set`);

let dockerImage;

const namespace =
  process.env.NAMESPACE ||
  fs.readFileSync('/var/run/secrets/kubernetes.io/serviceaccount/namespace', {
    encoding: 'utf8',
    flag: 'r',
  });

const revision = 'unknown' ||
  process.env.AG0_MODE === 'true'
    ? 'ag0'
    : fs
        .readFileSync(
          '/usr/src/agoric-sdk/packages/solo/public/git-revision.txt',
          {
            encoding: 'utf8',
            flag: 'r',
          },
        )
        .trim();

/**
 * @param {string} relativeUrl
 * @returns {Promise<any>}
 */
const makeKubernetesRequest = async relativeUrl => {
  const ca = await fs.readFile(
    '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt',
    'utf8',
  );
  const token = await fs.readFile(
    '/var/run/secrets/kubernetes.io/serviceaccount/token',
    'utf8',
  );
  const url = new URL(
    relativeUrl,
    'https://kubernetes.default.svc.cluster.local',
  );
  const response = await fetch(url.href, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/json',
    },
    agent: new https.Agent({ ca }),
  });
  return response.json();
};

const getMetricsRequest = async relativeUrl => {
  const url = new URL('http://localhost:26661/metrics');
  const response = await fetch(url.href);
  return response.text();
};

// eslint-disable-next-line no-unused-vars
async function getNodeId(node) {
  const response = await fetch(
    `http://${node}.${namespace}.svc.cluster.local:26657/status`,
  );
  return response.json();
}

async function getServices() {
  if (FAKE) {
    return new Map([
      ['validator-primary-ext', '1.1.1.1'],
      ['seed-ext', '1.1.1.2'],
    ]);
  }
  const services = await makeKubernetesRequest(
    `/api/v1/namespaces/${namespace}/services/`,
  );
  const map1 = new Map();
  for (const item of services.items) {
    const ingress = item.status?.loadBalancer?.ingress;
    if (ingress?.length > 0) {
      map1.set(item.metadata.name, ingress[0].ip);
    }
  }
  return map1;
}

const getNetworkConfig = async () => {
  const svc = await getServices();
  const file = FAKE
    ? './resources/network_info.json'
    : '/config/network/network_info.json';
  const buf = await fs.readFile(file, 'utf8');
  const ap = JSON.parse(buf);
  ap.chainName = chainId;
  ap.gci = `https://${NETNAME}.rpc${NETDOMAIN}:443/genesis`;
  ap.peers[0] = ap.peers[0].replace(
    'validator-primary.instagoric.svc.cluster.local',
    svc.get('validator-primary-ext') ||
      `${podname}.${namespace}.svc.cluster.local`,
  );
  ap.peers[0] = ap.peers[0].replace(
    'fb86a0993c694c981a28fa1ebd1fd692f345348b', `${NODE_ID}`,
  );
  ap.rpcAddrs = [`https://${NETNAME}.rpc${NETDOMAIN}:443`];
  ap.apiAddrs = [`https://${NETNAME}.api${NETDOMAIN}:443`];
  if (INCLUDE_SEED==='yes') {
    ap.seeds[0] = ap.seeds[0].replace(
      'seed.instagoric.svc.cluster.local',
      svc.get('seed-ext') || `seed.${namespace}.svc.cluster.local`,
    );
  } else {
    ap.seeds = [];
  }

  return JSON.stringify(ap);
};
class DataCache {
  constructor(fetchFunction, minutesToLive = 10) {
    this.millisecondsToLive = minutesToLive * 60 * 1000;
    this.fetchFunction = fetchFunction;
    this.cache = null;
    this.getData = this.getData.bind(this);
    this.resetCache = this.resetCache.bind(this);
    this.isCacheExpired = this.isCacheExpired.bind(this);
    this.fetchDate = new Date(0);
  }

  isCacheExpired() {
    return (
      this.fetchDate.getTime() + this.millisecondsToLive < new Date().getTime()
    );
  }

  getData() {
    if (!this.cache || this.isCacheExpired()) {
      console.log('fetch');
      return this.fetchFunction().then(data => {
        this.cache = data;
        this.fetchDate = new Date();
        return data;
      });
    } else {
      console.log('cache hit');

      return Promise.resolve(this.cache);
    }
  }

  resetCache() {
    this.fetchDate = new Date(0);
  }
}
const ipsCache = new DataCache(getServices, 0.1);
const networkConfig = new DataCache(getNetworkConfig, 0.5);
const metricsCache = new DataCache(getMetricsRequest, 0.1);

const publicapp = express();
const privateapp = express();
const faucetapp = express();
const publicport = 8001;
const privateport = 8002;
const faucetport = 8003;
const logReq = (req, res, next) => {
  const time = Date.now();
  res.on('finish', () => {
    console.log(
      JSON.stringify({
        time,
        dur: Date.now() - time,
        method: req.method,
        forwarded: req.get('X-Forwarded-For'),
        ip: req.ip,
        url: req.originalUrl,
        status: res.statusCode,
      }),
    );
  });
  next();
};

publicapp.use(logReq);
privateapp.use(logReq);
faucetapp.use(logReq);

publicapp.get('/', (req, res) => {
  const domain = NETDOMAIN;
  const netname = NETNAME;
  res.send(`
<html><head><title>Instagoric</title></head><body><pre>
██╗███╗   ██╗███████╗████████╗ █████╗  ██████╗  ██████╗ ██████╗ ██╗ ██████╗
██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██╔════╝ ██╔═══██╗██╔══██╗██║██╔════╝
██║██╔██╗ ██║███████╗   ██║   ███████║██║  ███╗██║   ██║██████╔╝██║██║     
██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║   ██║██║   ██║██╔══██╗██║██║     
██║██║ ╚████║███████║   ██║   ██║  ██║╚██████╔╝╚██████╔╝██║  ██║██║╚██████╗
╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝ ╚═════╝

Chain: ${chainId}${
    process.env.NETPURPOSE !== undefined
      ? `\nPurpose: ${process.env.NETPURPOSE}`
      : ''
  }
Revision: ${revision}
Docker Image: ${DOCKERIMAGE || dockerImage.split(':')[0]}:${DOCKERTAG || dockerImage.split(':')[1]}
Revision Link: <a href="https://github.com/Agoric/agoric-sdk/tree/${revision}">https://github.com/Agoric/agoric-sdk/tree/${revision}</a>
Network Config: <a href="https://${netname}${domain}/network-config">https://${netname}${domain}/network-config</a>
Docker Compose: <a href="https://${netname}${domain}/docker-compose.yml">https://${netname}${domain}/docker-compose.yml</a>
RPC: <a href="https://${netname}.rpc${domain}">https://${netname}.rpc${domain}</a>
gRPC: <a href="https://${netname}.grpc${domain}">https://${netname}.grpc${domain}</a>
API: <a href="https://${netname}.api${domain}">https://${netname}.api${domain}</a>
Explorer: <a href="https://${netname}.explorer${domain}">https://${netname}.explorer${domain}</a>
Faucet: <a href="https://${netname}.faucet${domain}">https://${netname}.faucet${domain}</a>
Logs: <a href='https://${netname}.logs${domain}/d/aduznatawfxmob/cluster-logs?orgId=1&viewPanel=1&from=now-1m&to=now&var-userQuery=resource.labels.container_name%3D"log-slog"'>https://${netname}.logs${domain}</a>

UIs:
Main-branch Wallet: <a href="https://main.wallet-app.pages.dev/wallet/">https://main.wallet-app.pages.dev/wallet/</a>
Main-branch Vaults: <a href="https://dapp-inter-test.pages.dev/?network=${netname}">https://dapp-inter-test.pages.dev/?network=${netname}</a>



----
See more at <a href="https://agoric.com">https://agoric.com</a>
</pre></body></html>                                                     
  `);
});

publicapp.get('/network-config', async (req, res) => {
  res.setHeader('Content-type', 'text/plain;charset=UTF-8');
  res.setHeader('Access-Control-Allow-Origin', '*');
  const result = await networkConfig.getData();
  res.send(result);
});

publicapp.get('/metrics-config', async (req, res) => {
  res.setHeader('Content-type', 'text/plain;charset=UTF-8');
  const result = await metricsCache.getData();
  res.send(result);
});

const dockerComposeYaml = (dockerimage, dockertag, netname, netdomain) => `\
version: "2.2"
services:
  ag-solo:
    image: ${dockerimage}:\${SDK_TAG:-${dockertag}}
    ports:
      - "\${HOST_PORT:-8000}:\${PORT:-8000}"
    volumes:
      - "ag-solo-state:/state"
      - "$HOME/.agoric:/root/.agoric"
    environment:
      - "AG_SOLO_BASEDIR=/state/\${SOLO_HOME:-${dockertag}}"
    entrypoint: ag-solo
    command:
      - setup
      - --webhost=0.0.0.0
      - --webport=\${PORT:-8000}
      - --netconfig=\${NETCONFIG_URL:-https://${netname}${netdomain}/network-config}
volumes:
  ag-solo-state:
`;

publicapp.get('/docker-compose.yml', (req, res) => {
  res.setHeader(
    'Content-disposition',
    'attachment; filename=docker-compose.yml',
  );
  res.setHeader('Content-type', 'text/x-yaml;charset=UTF-8');
  res.send(
    dockerComposeYaml(
      DOCKERIMAGE || dockerImage.split(':')[0],
      DOCKERTAG || dockerImage.split(':')[1],
      NETNAME,
      NETDOMAIN,
    ),
  );
});

privateapp.get('/', (req, res) => {
  res.send('welcome to instagoric');
});

privateapp.get('/ips', (req, res) => {
  ipsCache.getData().then(result => {
    if (result.size > 0) {
      res.send(JSON.stringify({ status: 1, ips: Object.fromEntries(result) }));
    } else {
      res.status(500).send(JSON.stringify({ status: 0, ips: {} }));
      ipsCache.resetCache();
    }
  });
});

privateapp.get('/genesis.json', async (req, res) => {
  try {
    const file = `/state/${chainId}/config/genesis_final.json`;
    if (await fs.pathExists(file)) {
      const buf = await fs.readFile(file, 'utf8');
      res.send(buf);
      return;
    }
  } catch (err) {
    console.error(err);
  }
  res.status(500).send('error');
});

privateapp.get('/repl', async (req, res) => {
  const svc = await ipsCache.getData();
  if (svc.length > 0) {
    const file = '/state/agoric.repl';
    let buf = await fs.readFile(file, 'utf8');
    buf = buf.replace(
      '127.0.0.1',
      svc.get('ag-solo-manual-ext') || '127.0.0.1',
    );
    res.send(buf);
  } else {
    res.status(500).send('error');
    ipsCache.resetCache();
  }
});

const addressToRequest = new Map();
const { publication, subscription } = makeSubscriptionKit();
const addRequest = (address, request) => {
  if (addressToRequest.has(address)) {
    request[0].status(429).send('error - already queued');
    return;
  }
  console.log('enqueued', address);
  addressToRequest.set(address, request);
  publication.updateState(address);
};

// Faucet worker.

const constructAmountToSend = (amount, denoms) => denoms.map(denom => `${amount}${denom}`).join(',');

const getDenoms = async () => {
  const result = await $`${agBinary} query bank total --limit=100 -o json`;
  const output = JSON.parse(result.stdout.trim());
  return output.supply.map((element) => element.denom);
}

const sendFunds = async (accountAddress, amounts) => {
  const exitCode = await $`\
          ${agBinary} tx bank send -b block \
  ${FAUCET_KEYNAME} ${accountAddress} ${amounts} \
  -y --keyring-backend test --keyring-dir=${agoricHome} \
  --chain-id=${chainId} --node http://localhost:26657 \
`.exitCode;

return exitCode;

} 

const startFaucetWorker = async () => {
  console.log('Starting Faucet worker!');

  const denomsInChain = await getDenoms();

  try {
    for await (const address of subscription) {
      // Handle request.
      console.log('dequeued', address);
      const request = addressToRequest.get(address);

      const [_a, command, clientType, denoms] = request;
      console.log("denoms", denoms);
      let exitCode = 1;
      switch (command) {
        case COMMANDS['SEND_AND_PROVISION_IST']: {
          if (!AG0_MODE) {

            exitCode = await sendFunds(address, CLIENT_AMOUNT || constructAmountToSend(BASE_AMOUNT, ['uist']));
            if (exitCode === 0) {
              exitCode = await $`\
            ${agBinary} tx swingset provision-one faucet_provision ${address} ${clientType} \
  -b block --from ${FAUCET_KEYNAME} \
  -y --keyring-backend test --keyring-dir=${agoricHome} \
  --chain-id=${chainId} --node http://localhost:26657 \
`.exitCode;
            }
          }
          break;
        }
        case COMMANDS["SEND_BLD/IBC"]: {
          const ibcDenoms = denomsInChain.filter(denom => denom.startsWith('ibc'));
          exitCode = await sendFunds(address, DELEGATE_AMOUNT || constructAmountToSend(BASE_AMOUNT, ['ubld', ...ibcDenoms]));
          break;
        }
        case COMMANDS["FUND_PROV_POOL"]: {
          exitCode = await sendFunds(PROVISIONING_POOL_ADDR, DELEGATE_AMOUNT || constructAmountToSend(BASE_AMOUNT, denomsInChain));
          break;
        }

        case COMMANDS["CUSTOM_DENOMS_LIST"]: {
            console.log('HERE');
            exitCode = await sendFunds(address, DELEGATE_AMOUNT || constructAmountToSend(BASE_AMOUNT, Array.isArray(denoms) ? denoms : [denoms]));
            break;

        }
        default: {
          console.log('unknown command');
          request[0].status(500).send('failure');
          // eslint-disable-next-line no-continue
          continue;
        }
      }

      addressToRequest.delete(address);
      if (exitCode === 0) {
        console.log('Success');
        request[0].status(200).send('success');
      } else {
        console.log('Failure');
        request[0].status(500).send('failure');
      }
    }
  } catch (e) {
    console.error('Faucet worker died', e);
    await sleep(3000);
    startFaucetWorker();
  }
};
startFaucetWorker();

privateapp.listen(privateport, () => {
  console.log(`privateapp listening on port ${privateport}`);
});


faucetapp.get('/', async (req, res) => {
  // Not handling pagination as it is used for testing. Limit 100 shoud suffice

  const denoms = await getDenoms();
  let denomHtml = '';
  denoms.forEach((denom) => {
    // denomHtml += `<option value=${element.denom}> ${element.denom}</option>`;
    denomHtml += `<label><input type="checkbox" name="denoms" value=${denom}> ${denom} </label>`;
  })
  const denomsDropDownHtml =`<div class="dropdown"> <div class="dropdown-content"> ${denomHtml}</div> </div>`
  
  const clientText = !AG0_MODE
    ? `<input type="radio" id="client" name="command" value=${COMMANDS["SEND_AND_PROVISION_IST"]} onclick="toggleRadio(event)">
<label for="client">send IST and provision </label>
<select name="clientType">
<option value="SMART_WALLET">smart wallet</option>
<option value="REMOTE_WALLET">ag-solo</option>
</select>`
    : '';
  res.send(
    `<html><head><title>Faucet</title>
    <script>
    function toggleRadio(event) {
            console.log(event.target.value);
            var value = event.target.value
            var field = document.getElementById('denoms');

            console.log(field);
            if (value === "custom_denoms_list") {
              console.log("HERE");            
              field.style.display = 'block';
            } else if (field.style.display === 'block') {  
               field.style.display = 'none';
            }
      }
    </script>
    
    <style>
      
      .dropdown {
      overflow: scroll;
      height: 120px;
      width: fit-content;
      }

      .dropdown-content {
        display: block;
        background-color: #f9f9f9;
        min-width: 160px;
        box-shadow: 0px 8px 16px 0px rgba(0,0,0,0.2);
      }

      .dropdown-content label {
        display: block;
        margin-top: 10px;
      }
      
      .denomsClass {
        display: none;
      }
</style>
    </head><body><h1>welcome to the faucet</h1>
<form action="/go" method="post">
<label for="address">Address:</label> <input id="address" name="address" type="text" /><br>
Request: <input type="radio" id="delegate" name="command" value=${COMMANDS["SEND_BLD/IBC"]} checked="checked" onclick="toggleRadio(event)">
<label for="delegate">send BLD/IBC toy tokens</label>
${clientText}

<input type="radio" id=${COMMANDS["CUSTOM_DENOMS_LIST"]} name="command" value=${COMMANDS["CUSTOM_DENOMS_LIST"]} onclick="toggleRadio(event)"}>
<label for=${COMMANDS["CUSTOM_DENOMS_LIST"]}> Select Custom Denoms </label>

<br>


<br>
<div id='denoms' class="denomsClass"> 
Denoms: ${denomsDropDownHtml} <br> <br>
</div>
<input type="submit" />
</form>
<br>

<br>
<form action="/go" method="post">
<input type="hidden" name="command" value=${COMMANDS["FUND_PROV_POOL"]} /><input type="submit" value="fund provision pool" />
</form>
</body></html>
`,
  );
});

faucetapp.get('/get-denom', async (req, res) => {
  const result = await $`${agBinary} query bank total --chain-id=${chainId} -o json | jq '.supply[].denom'`;
  const output = result.stdout.trim();
  console.log(output);
  res.send(output);
});

faucetapp.use(
  express.urlencoded({
    extended: true,
  }),
);

faucetapp.post('/go', (req, res) => {
  const { command, address, clientType, denoms } = req.body;
  if (
    ((command === COMMANDS["SEND_AND_PROVISION_IST"] &&
      ['SMART_WALLET', 'REMOTE_WALLET'].includes(clientType)) ||
      command === COMMANDS['SEND_BLD/IBC'] ||
      command === COMMANDS["FUND_PROV_POOL"] ||
      command === COMMANDS["CUSTOM_DENOMS_LIST"] && denoms && denoms.length > 0) &&
    (command === COMMANDS["FUND_PROV_POOL"] || (typeof address === 'string' &&
    address.length === 45 &&
    /^agoric1[0-9a-zA-Z]{38}$/.test(address)))
  ) {
    addRequest(address, [res, command, clientType, denoms]);
  } else {
    res.status(403).send('invalid form');
  }
});

faucetapp.listen(faucetport, () => {
  console.log(`faucetapp listening on port ${faucetport}`);
});

if (FAKE) {
  dockerImage = 'asdf:unknown';
} else {
  const statefulSet = await makeKubernetesRequest(
    `/apis/apps/v1/namespaces/${namespace}/statefulsets/${podname}`,
  );
  dockerImage = statefulSet.spec.template.spec.containers[0].image;
}
publicapp.listen(publicport, () => {
  console.log(`publicapp listening on port ${publicport}`);
});
