// @ts-check
import './lockdown.js';

import express from 'express';
import https from 'https';
import process from 'process';
import tmp from 'tmp';
import { $, fetch, fs, nothrow, sleep } from 'zx';

import { makeSubscriptionKit } from '@agoric/notifier';

const { details: X } = assert;

const BASE_AMOUNT = 25000000;
// Adding here to avoid ReferenceError for local server. Not needed for k8
let CLUSTER_NAME;

const CLIENT_AMOUNT = process.env.CLIENT_AMOUNT || `${BASE_AMOUNT}ibc/toyusdc`;
const DELEGATE_AMOUNT =
  process.env.DELEGATE_AMOUNT ||
  `${BASE_AMOUNT * 3}${
    process.env.BLD_DENOM
  },${BASE_AMOUNT}ibc/toyatom,${BASE_AMOUNT}ibc/toyellie,${BASE_AMOUNT}ibc/toyusdc,${BASE_AMOUNT}ibc/toyollie`;

const COMMANDS = {
  'SEND_BLD/IBC': 'send_bld_ibc',
  SEND_AND_PROVISION_IST: 'send_ist_and_provision',
  FUND_PROV_POOL: 'fund_provision_pool',
  CUSTOM_DENOMS_LIST: 'custom_denoms_list',
};

const DOCKERTAG = process.env.DOCKERTAG; // Optional.
const DOCKERIMAGE = process.env.DOCKERIMAGE; // Optional.
const FAKE = process.env.FAKE || process.argv[2] === '--fake';
const FILE_ENCODING = 'utf8';
const FAUCET_KEYNAME =
  process.env.FAUCET_KEYNAME ||
  process.env.WHALE_KEYNAME ||
  process.env.SELF_KEYNAME;
const INCLUDE_SEED = process.env.SEED_ENABLE || 'yes';
const NETDOMAIN = process.env.NETDOMAIN || '.agoric.net';
const NETNAME = process.env.NETNAME || 'devnet';
const podname =
  process.env.POD_NAME || process.env.PRIMARY_VALIDATOR_STATEFUL_SET_NAME;
const RPC_PORT = Number(process.env.RPC_PORT);
const TRANSACTION_STATUS = {
  FAILED: 1000,
  NOT_FOUND: 1001,
  SUCCESSFUL: 1002,
};

if (FAKE) {
  console.log('FAKE MODE');
  const tmpDir = await new Promise((resolve, reject) => {
    tmp.dir({ prefix: 'faucet', postfix: 'home' }, (err, path) =>
      err ? reject(err) : resolve(path),
    );
  });
  // Create the temporary key.
  console.log(`Creating temporary key`, { tmpDir, FAUCET_KEYNAME });
  await $`agd --home=${tmpDir} keys --keyring-backend=test add ${FAUCET_KEYNAME}`;
  if (!process.env.AGORIC_HOME) process.env.AGORIC_HOME = tmpDir;
}

const agoricHome = process.env.AGORIC_HOME;
assert(agoricHome, X`AGORIC_HOME not set`);

const chainId = process.env.CHAIN_ID;
assert(chainId, X`CHAIN_ID not set`);

let dockerImage;

const namespace =
  process.env.NAMESPACE ||
  fs.readFileSync(String(process.env.NAMESPACE_PATH), {
    encoding: FILE_ENCODING,
    flag: 'r',
  });

const revision = FAKE
  ? 'fake_revision'
  : fs
      .readFileSync(
        `${process.env.SDK_ROOT_PATH}/packages/solo/public/git-revision.txt`,
        {
          encoding: FILE_ENCODING,
          flag: 'r',
        },
      )
      .trim();

const getMetricsRequest = async () => {
  const url = new URL('http://localhost:26661/metrics');
  const response = await fetch(url.href);
  return response.text();
};

const getNetworkConfig = async () => {
  const svc = await getServices();
  const file = FAKE
    ? './resources/network_info.json'
    : '/config/network/network_info.json';
  const buf = await fs.readFile(file, FILE_ENCODING);
  const ap = JSON.parse(buf);
  ap.chainName = chainId;
  ap.gci = `https://${NETNAME}.rpc${NETDOMAIN}:443/genesis`;
  const primaryValidatorNodeId = await getNodeId(
    String(process.env.PRIMARY_VALIDATOR_STATEFUL_SET_NAME),
  );

  ap.peers = [
    `${primaryValidatorNodeId}@${
      svc.get(process.env.PRIMARY_VALIDATOR_SERVICE_NAME) ||
      `${process.env.PRIMARY_VALIDATOR_STATEFUL_SET_NAME}.${namespace}.svc.cluster.local`
    }`,
  ];

  ap.rpcAddrs = [`https://${NETNAME}.rpc${NETDOMAIN}:443`];
  ap.apiAddrs = [`https://${NETNAME}.api${NETDOMAIN}:443`];

  if (INCLUDE_SEED === 'yes') {
    const seedNodeId = await getNodeId(
      String(process.env.SEED_STATEFUL_SET_NAME),
    );
    ap.seeds = [
      `${seedNodeId}@${
        svc.get(process.env.SEED_SERVICE_NAME) ||
        `${process.env.SEED_STATEFUL_SET_NAME}.${namespace}.svc.cluster.local`
      }`,
    ];
  } else ap.seeds = [];

  return JSON.stringify(ap);
};

/**
 * @param {string} service_name
 */
const getNodeId = async service_name => {
  while (true) {
    const response = await fetch(
      `http://${service_name}.${namespace}.svc.cluster.local:${process.env.RPC_PORT}/status`,
      {
        signal: AbortSignal.timeout(15 * 1000),
      },
    );
    if (!response.ok)
      await new Promise(resolve => setTimeout(resolve, 5 * 1000));
    else
      return /** @type {Promise<{result: {node_info: {id: string}}}>} */ (
        response.json()
      ).then(({ result }) => result.node_info.id);
  }
};

const getServices = async () => {
  if (FAKE)
    return new Map([
      [process.env.PRIMARY_VALIDATOR_SERVICE_NAME, '1.1.1.1'],
      [process.env.SEED_SERVICE_NAME, '1.1.1.2'],
    ]);

  const services = await makeKubernetesRequest(
    `/api/v1/namespaces/${namespace}/services/`,
  );
  const map1 = new Map();
  for (const item of services.items) {
    // Cluster IP will only be used in case there is no Loadbalancer infrastructure
    // which should only be in the case of a local cluster deployment
    const ip =
      item.status?.loadBalancer?.ingress?.[0].ip ||
      (item.spec?.clusterIPs || []).find(Boolean);
    if (ip) map1.set(item.metadata.name, ip);
  }
  return map1;
};

/**
 * @param {string} relativeUrl
 * @returns {Promise<any>}
 */
const makeKubernetesRequest = async relativeUrl => {
  const ca = await fs.readFile(String(process.env.CA_PATH), FILE_ENCODING);
  const token = await fs.readFile(
    String(process.env.TOKEN_PATH),
    FILE_ENCODING,
  );
  const url = new URL(
    relativeUrl,
    'https://kubernetes.default.svc.cluster.local',
  );
  const response = await fetch(url.href, {
    agent: new https.Agent({ ca }),
    headers: {
      Accept: 'application/json',
      Authorization: `Bearer ${token}`,
    },
  });
  return response.json();
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

publicapp.get('/', (_, res) => {
  const domain = NETDOMAIN;
  const netname = NETNAME;
  const gcloudLoggingDatasource = 'P470A85C5170C7A1D';
  const logsQuery = {
    '62l': {
      datasource: gcloudLoggingDatasource,
      queries: [
        {
          queryText: `resource.labels.container_name=\"log-slog\" resource.labels.namespace_name=\"${namespace}\" resource.labels.cluster_name=\"${CLUSTER_NAME}\"`,
        },
      ],
    },
  };
  const logsUrl = `https://monitor${domain}/explore?schemaVersion=1&panes=${encodeURI(
    JSON.stringify(logsQuery),
  )}&orgId=1`;
  const dashboardUrl = `https://monitor${domain}/d/cdzujrg5sxvy8g/agoric-chain-metrics-bare-metal?var-cluster=${CLUSTER_NAME}&var-namespace=${namespace}&var-chain_id=${chainId}&orgId=1`;
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
Docker Image: ${DOCKERIMAGE || dockerImage.split(':')[0]}:${
    DOCKERTAG || dockerImage.split(':')[1]
  }
Revision Link: <a href="https://github.com/Agoric/agoric-sdk/tree/${revision}">https://github.com/Agoric/agoric-sdk/tree/${revision}</a>
Network Config: <a href="https://${netname}${domain}/network-config">https://${netname}${domain}/network-config</a>
Docker Compose: <a href="https://${netname}${domain}/docker-compose.yml">https://${netname}${domain}/docker-compose.yml</a>
RPC: <a href="https://${netname}.rpc${domain}">https://${netname}.rpc${domain}</a>
gRPC: <a href="https://${netname}.grpc${domain}">https://${netname}.grpc${domain}</a>
API: <a href="https://${netname}.api${domain}">https://${netname}.api${domain}</a>
Explorer: <a href="https://${netname}.explorer${domain}">https://${netname}.explorer${domain}</a>
Faucet: <a href="https://${netname}.faucet${domain}">https://${netname}.faucet${domain}</a>
Logs: <a href=${logsUrl}>Click Here</a>
Monitoring Dashboard: <a href=${dashboardUrl}>Click Here</a>
VStorage: <a href="https://vstorage.agoric.net/?path=&endpoint=https://${
    netname === 'followmain' ? 'main-a' : netname
  }.rpc.agoric.net">https://vstorage.agoric.net/?endpoint=https://${
    netname === 'followmain' ? 'main-a' : netname
  }.rpc.agoric.net</a>

UIs:
Main-branch Wallet: <a href="https://main.wallet-app.pages.dev/wallet/">https://main.wallet-app.pages.dev/wallet/</a>
Main-branch Vaults: <a href="https://dapp-inter-test.pages.dev/?network=${netname}">https://dapp-inter-test.pages.dev/?network=${netname}</a>

----
See more at <a href="https://agoric.com">https://agoric.com</a>
</pre></body></html>
  `);
});

publicapp.get('/network-config', async (_, res) => {
  res.setHeader('Content-type', 'text/plain;charset=UTF-8');
  res.setHeader('Access-Control-Allow-Origin', '*');
  const result = await networkConfig.getData();
  res.send(result);
});

publicapp.get('/metrics-config', async (_, res) => {
  res.setHeader('Content-type', 'text/plain;charset=UTF-8');
  const result = await metricsCache.getData();
  res.send(result);
});

/**
 * @param {string} dockerimage
 * @param {string} dockertag
 * @param {string} netname
 * @param {string} netdomain
 */
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

publicapp.get('/docker-compose.yml', (_, res) => {
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

privateapp.get('/', (_, res) => {
  res.send('welcome to instagoric');
});

privateapp.get('/ips', (_, res) => {
  ipsCache.getData().then(result => {
    if (result.size > 0)
      res.send(JSON.stringify({ status: 1, ips: Object.fromEntries(result) }));
    else {
      res.status(500).send(JSON.stringify({ status: 0, ips: {} }));
      ipsCache.resetCache();
    }
  });
});

privateapp.get('/genesis.json', async (_, res) => {
  try {
    const file = String(process.env.GENESIS_FILE_PATH);
    if (await fs.pathExists(file)) {
      const buf = await fs.readFile(file, FILE_ENCODING);
      res.send(buf);
      return;
    }
  } catch (err) {
    console.error(err);
  }
  res.status(500).send('error');
});

privateapp.get('/repl', async (_, res) => {
  const svc = await ipsCache.getData();
  if (svc.length > 0) {
    const file = '/state/agoric.repl';
    let buf = await fs.readFile(file, FILE_ENCODING);
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

/**
 * @param {string} address
 * @param {*} request
 */
const addRequest = (address, request) => {
  if (addressToRequest.has(address))
    return request[0].status(429).send('error - already queued');

  console.log('enqueued', address);
  addressToRequest.set(address, request);
  publication.updateState(address);
};

/**
 * @param {string} amount
 * @param {Array<string>} denoms
 */
const constructAmountToSend = (amount, denoms) =>
  denoms.map(denom => `${amount}${denom}`).join(',');

const getDenoms = async () => {
  // Not handling pagination as it is used for testing. Limit 100 shoud suffice
  const result = await $`agd query bank total --limit 100 --output json`;
  /**
   * @type {{
   *  supply: Array<{amount: string; denom: string}>;
   *  pagination: { next_key: string; total: string; }
   * }}
   */
  const output = JSON.parse(result.stdout.trim());
  return output.supply.map(({ denom }) => denom);
};

/**
 * Returns the status of a transaction against hash `txHash`.
 * The status is one of the values from `TRANSACTION_STATUS`
 * @param {string} txHash
 * @returns {Promise<number>}
 */
const getTransactionStatus = async txHash => {
  let { exitCode, stderr, stdout } = await nothrow($`\
    agd query tx ${txHash} \
    --chain-id=${chainId} \
    --home=${agoricHome} \
    --node=http://localhost:${RPC_PORT} \
    --output=json \
    --type=hash \
  `);
  exitCode = exitCode ?? 1;

  // This check is brittle as this can also happen in case
  // an invalid txhash was provided. So there is no reliable
  // distinction between the case of invalid txhash and a
  // transaction currently in the mempool. We could use search
  // endpoint but that seems overkill to cover a case where
  // the only the deliberate use of invalid hash can effect the user
  if (exitCode && stderr.includes(`tx (${txHash}) not found`))
    return TRANSACTION_STATUS.NOT_FOUND;

  const code = Number(JSON.parse(stdout).code);
  return code ? TRANSACTION_STATUS.FAILED : TRANSACTION_STATUS.SUCCESSFUL;
};

/**
 * @param {string} address
 * @param {string} clientType
 * @param {string} txHash
 * @returns {Promise<void>}
 */
const pollForProvisioning = async (address, clientType, txHash) => {
  const status = await getTransactionStatus(txHash);
  status === TRANSACTION_STATUS.NOT_FOUND
    ? setTimeout(() => pollForProvisioning(address, clientType, txHash), 2000)
    : status === TRANSACTION_STATUS.SUCCESSFUL
    ? await provisionAddress(address, clientType)
    : console.log(
        `Not provisioning address "${address}" of type "${clientType}" as transaction "${txHash}" failed`,
      );
};

/**
 * @param {string} address
 * @param {string} clientType
 * @returns {Promise<void>}
 */
const provisionAddress = async (address, clientType) => {
  let { exitCode, stderr } = await nothrow($`\
    agd tx swingset provision-one faucet_provision ${address} ${clientType} \
    --broadcast-mode=block \
    --chain-id=${chainId} \
    --from=${FAUCET_KEYNAME} \
    --keyring-backend=test \
    --keyring-dir=${agoricHome} \
    --node=http://localhost:${RPC_PORT} \
    --yes \
  `);
  exitCode = exitCode ?? 1;

  if (exitCode)
    console.log(
      `Failed to provision address "${address}" of type "${clientType}" with error message: ${stderr}`,
    );
};

/**
 * Send funds to `address`.
 * It only waits for the transaction
 * checks and doesn't wait for the
 * transaction to actually be included
 * in a block. The returned transaction
 * hash can be used to get the current status
 * of the transaction later
 * @param {string} address
 * @param {string} amount
 * @returns {Promise<[number, string]>}
 */
const sendFunds = async (address, amount) => {
  let { exitCode, stdout } = await nothrow($`\
    agd tx bank send ${FAUCET_KEYNAME} ${address} ${amount} \
    --broadcast-mode=sync \
    --chain-id=${chainId} \
    --keyring-backend=test \
    --keyring-dir=${agoricHome} \
    --node=http://localhost:${RPC_PORT} \
    --output=json \
    --yes \
  `);
  exitCode = exitCode ?? 1;

  if (exitCode) return [exitCode, ''];
  return [exitCode, String(JSON.parse(stdout).txhash)];
};

// Faucet worker.

const startFaucetWorker = async () => {
  console.log('Starting Faucet worker!');

  try {
    for await (const address of subscription) {
      console.log(`dequeued address ${address}`);
      const request = addressToRequest.get(address);

      const [response, command, clientType, denoms, amount] = request;
      let exitCode = 1;
      let txHash = '';

      console.log(`Processing "${command}" for address "${address}"`);

      switch (command) {
        case COMMANDS.SEND_AND_PROVISION_IST: {
          [exitCode, txHash] = await sendFunds(address, CLIENT_AMOUNT);
          if (!exitCode) pollForProvisioning(address, clientType, txHash);
          break;
        }
        case COMMANDS['SEND_BLD/IBC']: {
          [exitCode, txHash] = await sendFunds(address, DELEGATE_AMOUNT);
          break;
        }
        case COMMANDS.FUND_PROV_POOL: {
          [exitCode, txHash] = await sendFunds(
            String(process.env.PROVISIONING_ADDRESS),
            DELEGATE_AMOUNT,
          );
          break;
        }
        case COMMANDS.CUSTOM_DENOMS_LIST: {
          [exitCode, txHash] = await sendFunds(
            address,
            constructAmountToSend(
              String(amount ? Number(amount) * 1000_000 : BASE_AMOUNT),
              Array.isArray(denoms) ? denoms : [denoms],
            ),
          );
          break;
        }
        default: {
          console.log('unknown command');
          response.status(500).send('failure');
          continue;
        }
      }

      addressToRequest.delete(address);
      if (exitCode === 0) {
        console.log(
          `Successfuly processed "${command}" for address "${address}"`,
        );
        response.redirect(`/transaction-status/${txHash}`);
      } else {
        console.log(`Failed to process "${command}" for address "${address}"`);
        response.status(500).send('failure');
      }
    }
  } catch (e) {
    console.error('Faucet worker died', e);
    await sleep(3000);
    startFaucetWorker();
  }
};

startFaucetWorker();

faucetapp.get('/', async (req, res) => {
  const denoms = await getDenoms();
  let denomHtml = '';
  denoms.forEach(denom => {
    denomHtml += `<label><input type="checkbox" name="denoms" value=${denom}> ${denom} </label>`;
  });
  const denomsDropDownHtml = `<div class="dropdown"> <div class="dropdown-content"> ${denomHtml}</div> </div>`;
  const maxTokenAmount = 100;

  res.send(
    `<html><head><title>Faucet</title>
    <script>
    function toggleRadio(event) {
            var field = document.getElementById('denoms');

            if (event.target.value === "${COMMANDS.CUSTOM_DENOMS_LIST}") {        
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
        border: 1px solid #ccc;
        padding: 10px;
        box-shadow: 0px 8px 16px rgba(0, 0, 0, 0.2);
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
Request: <input type="radio" id="delegate" name="command" value=${COMMANDS['SEND_BLD/IBC']} checked="checked" onclick="toggleRadio(event)">
<label for="delegate">send BLD/IBC toy tokens</label>
<input type="radio" id="client" name="command" value=${COMMANDS.SEND_AND_PROVISION_IST} onclick="toggleRadio(event)">
<label for="client">send IST and provision</label>
<select name="clientType">
<option value="SMART_WALLET">smart wallet</option>
<option value="REMOTE_WALLET">ag-solo</option>
</select>

<input type="radio" id=${COMMANDS.CUSTOM_DENOMS_LIST} name="command" value=${COMMANDS.CUSTOM_DENOMS_LIST} onclick="toggleRadio(event)"}>
<label for=${COMMANDS.CUSTOM_DENOMS_LIST}> Select Custom Denoms </label>

<br>


<br>
<div id='denoms' class="denomsClass"> 
Denoms: ${denomsDropDownHtml} <br> <br>
<label for="amount">Amount:</label>
<input type="number" id="amount" 
       name="amount" 
       step="any" 
       placeholder="Enter amount" 
       max="${maxTokenAmount}" 
       value="25"> 
<br> 
<small>The default amount is 25, but you can enter any value up to ${maxTokenAmount}.</small>
<br> <br>
</div>
<input type="submit" />
</form>
<br>

<br>
<form action="/go" method="post">
<input type="hidden" name="command" value=${COMMANDS.FUND_PROV_POOL} /><input type="submit" value="fund provision pool" />
</form>
</body></html>
`,
  );
});

faucetapp.use(
  express.urlencoded({
    extended: true,
  }),
);

faucetapp.post('/go', (req, res) => {
  const { address, amount, clientType, command, denoms } =
    /** @type {{ address: string; amount: number; clientType: string; command: string; denoms: Array<string>; }} */ (
      req.body
    );

  const MAX_AMOUNT = 100;

  if (amount > MAX_AMOUNT)
    res
      .status(400)
      .json({ error: `Amount exceeds maximum limit of ${MAX_AMOUNT}` });
  else if (
    (command === COMMANDS.SEND_AND_PROVISION_IST ||
      command === COMMANDS['SEND_BLD/IBC'] ||
      command === COMMANDS.FUND_PROV_POOL ||
      (command === COMMANDS.CUSTOM_DENOMS_LIST && !!denoms?.length)) &&
    (command === COMMANDS.FUND_PROV_POOL ||
      /^agoric1[0-9a-zA-Z]{38}$/.test(String(address)))
  )
    addRequest(address, [res, command, clientType, denoms, amount]);
  else res.status(403).send('invalid form');
});

faucetapp.get('/api/transaction-status/:txhash', async (req, res) => {
  const { txhash } = req.params;
  const transactionStatus = await getTransactionStatus(txhash);
  res.send({ transactionStatus }).status(200);
});

faucetapp.get('/transaction-status/:txhash', (req, res) => {
  const { txhash } = req.params;

  const mainPageLink = `<a href="/">Go to Main Page</a>`;

  if (txhash)
    res.status(200).send(
      `
      <html>
        <head>
          <script>
            var fetchTransactionStatus = function() {
              fetch("/api/transaction-status/${txhash}")
              .then(async function(response) {
                var json = await response.json();
                if (json.transactionStatus === ${TRANSACTION_STATUS.NOT_FOUND}) setTimeout(fetchTransactionStatus, 2000);
                else if (json.transactionStatus === ${TRANSACTION_STATUS.SUCCESSFUL}) document.body.innerHTML = \`
                  <h3>Your transaction "${txhash}" was successfull</h3>
                  ${mainPageLink}
                \`;
                else
                  document.body.innerHTML = \`
                    <h3>Your transaction "${txhash}" failed</h3>
                    ${mainPageLink}
                  \`;
              })
              .catch(function(error) {
                console.log("error: ", error);
                setTimeout(fetchTransactionStatus, 2000);
              })
            }
            fetchTransactionStatus();
          </script>
          <style>
            .loader {
              animation: spin 2s linear infinite;
              border: 8px solid #000000;
              border-radius: 50%;
              border-top: 8px solid #F5F5F5;
              height: 32px;
              width: 32px;
            }

            @keyframes spin {
              0% { transform: rotate(0deg); }
              100% { transform: rotate(360deg); }
            }
          </style>
          <title>Faucet</title>
        </head>
        <body style="align-items:center; display:flex; flex-direction:column;">
          <h1 style="width:100%;">Your transaction was enqueued</h1>
          <p style="width:100%;">Now sit back and relax while your transaction is included in a block</p>
          <div class="loader"></div>
        </body>
      </html>
      `,
    );
  else res.status(400).send('invalid form');
});

if (FAKE) dockerImage = 'asdf:unknown';
else {
  const statefulSet = await makeKubernetesRequest(
    `/apis/apps/v1/namespaces/${namespace}/statefulsets/${podname}`,
  );
  dockerImage = statefulSet.spec.template.spec.containers[0].image;
}

faucetapp.listen(faucetport, () =>
  console.log(`faucetapp listening on port ${faucetport}`),
);

privateapp.listen(privateport, () =>
  console.log(`privateapp listening on port ${privateport}`),
);

publicapp.listen(publicport, () =>
  console.log(`publicapp listening on port ${publicport}`),
);
