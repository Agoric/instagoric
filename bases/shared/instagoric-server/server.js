// @ts-check
import './lockdown.js';

import process from 'process';
import express from 'express';
import tmp from 'tmp';
import { $, fs, sleep } from 'zx';
import {
  BASE_AMOUNT,
  CLIENT_AMOUNT,
  DELEGATE_AMOUNT,
  COMMANDS,
  PROVISIONING_POOL_ADDR,
  DOCKERTAG,
  DOCKERIMAGE,
  FAUCET_KEYNAME,
  NETNAME,
  NETDOMAIN,
  TRANSACTION_STATUS,
  AG0_MODE,
  agBinary,
  FAKE,
  chainId,
  namespace,
  revision,
  ipsCache,
  networkConfig,
  metricsCache,
  dockerImage
} from './constants.js';
import {
  dockerComposeYaml,
  getTransactionStatus,
  pollForProvisioning,
  sendFunds,
  constructAmountToSend,
  getDenoms,
  logRequest
} from './utils.js';
import { makeSubscriptionKit } from '@agoric/notifier';

// Adding here to avoid ReferenceError for local server. Not needed for k8
let CLUSTER_NAME;

if (FAKE) {
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

const publicapp = express();
const privateapp = express();
const faucetapp = express();
const publicport = 8001;
const privateport = 8002;
const faucetport = 8003;


publicapp.use(logRequest);
privateapp.use(logRequest);
faucetapp.use(logRequest);

publicapp.get('/', (req, res) => {
  const domain = NETDOMAIN;
  const netname = NETNAME;
  const gcloudLoggingDatasource = 'P470A85C5170C7A1D'
  const logsQuery = { "62l": { "datasource": gcloudLoggingDatasource, "queries": [{ "queryText": `resource.labels.container_name=\"log-slog\" resource.labels.namespace_name=\"${namespace}\" resource.labels.cluster_name=\"${CLUSTER_NAME}\"`}] } }
  const logsUrl = `https://monitor${domain}/explore?schemaVersion=1&panes=${encodeURI(JSON.stringify(logsQuery))}&orgId=1`
  const dashboardUrl = `https://monitor${domain}/d/cdzujrg5sxvy8f/agoric-chain-metrics?var-cluster=${CLUSTER_NAME}&var-namespace=${namespace}&var-chain_id=${chainId}&orgId=1`
  res.send(`
<html><head><title>Instagoric</title></head><body><pre>
██╗███╗   ██╗███████╗████████╗ █████╗  ██████╗  ██████╗ ██████╗ ██╗ ██████╗
██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██╔════╝ ██╔═══██╗██╔══██╗██║██╔════╝
██║██╔██╗ ██║███████╗   ██║   ███████║██║  ███╗██║   ██║██████╔╝██║██║
██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║   ██║██║   ██║██╔══██╗██║██║
██║██║ ╚████║███████║   ██║   ██║  ██║╚██████╔╝╚██████╔╝██║  ██║██║╚██████╗
╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝ ╚═════╝

Chain: ${chainId}${process.env.NETPURPOSE !== undefined
      ? `\nPurpose: ${process.env.NETPURPOSE}`
      : ''
    }
Revision: ${revision}
Docker Image: ${DOCKERIMAGE || dockerImage.split(':')[0]}:${DOCKERTAG || dockerImage.split(':')[1]
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
VStorage: <a href="https://vstorage.agoric.net/?path=&endpoint=https://${netname === 'followmain' ? 'main-a' : netname}.rpc.agoric.net">https://vstorage.agoric.net/?endpoint=https://${netname === 'followmain' ? 'main-a' : netname}.rpc.agoric.net</a>

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
const startFaucetWorker = async () => {
  console.log('Starting Faucet worker!');

  try {
    for await (const address of subscription) {
      console.log(`dequeued address ${address}`);
      const request = addressToRequest.get(address);

      const [response, command, clientType, denoms] = request;
      let exitCode = 1;
      let txHash = '';

      console.log(`Processing "${command}" for address "${address}"`);

      switch (command) {
        case 'client':
        case COMMANDS['SEND_AND_PROVISION_IST']: {
          if (!AG0_MODE) {

            [exitCode, txHash] = await sendFunds(address, CLIENT_AMOUNT);
            if (!exitCode) {
              pollForProvisioning(address, clientType, txHash);
            }
          }
          break;
        }
        case 'delegate':
        case COMMANDS["SEND_BLD/IBC"]: {
          [exitCode, txHash] = await sendFunds(address, DELEGATE_AMOUNT);
          break;
        }
        case 'delegate':
        case COMMANDS["FUND_PROV_POOL"]: {
          [exitCode, txHash] = await sendFunds(PROVISIONING_POOL_ADDR, DELEGATE_AMOUNT);
          break;
        }
        case COMMANDS["CUSTOM_DENOMS_LIST"]: {
          [exitCode, txHash] = await sendFunds(address, constructAmountToSend(BASE_AMOUNT, Array.isArray(denoms) ? denoms : [denoms]));
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

privateapp.listen(privateport, () => {
  console.log(`privateapp listening on port ${privateport}`);
});


faucetapp.get('/', async (req, res) => {

  const denoms = await getDenoms();
  let denomHtml = '';
  denoms.forEach((denom) => {
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
            var field = document.getElementById('denoms');

            if (event.target.value === "${COMMANDS['CUSTOM_DENOMS_LIST']}") {        
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

faucetapp.use(
  express.urlencoded({
    extended: true,
  }),
);

faucetapp.post('/go', (req, res) => {
  const { command, address, clientType, denoms } = req.body;

  if (
    ((command === COMMANDS["SEND_AND_PROVISION_IST"] || command === 'client' &&
      ['SMART_WALLET', 'REMOTE_WALLET'].includes(clientType)) ||
      command === 'delegate' || command === COMMANDS['SEND_BLD/IBC'] ||
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

faucetapp.listen(faucetport, () => {
  console.log(`faucetapp listening on port ${faucetport}`);
});


publicapp.listen(publicport, () => {
  console.log(`publicapp listening on port ${publicport}`);
});
