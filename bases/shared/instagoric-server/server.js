// @ts-check
import './lockdown.js';

import process from 'process';
import express from 'express';
import tmp from 'tmp';
import { $, fetch, fs, nothrow, sleep } from 'zx';
import {
  getTransactionStatus,
  sendFunds,
  getDockerImage,
  getServices,
  getNetworkConfig,
  dockerComposeYaml,
  DataCache
} from './utils.js';
import {
  AG0_MODE,
  COMMANDS,
  BASE_AMOUNT,
  CLIENT_AMOUNT,
  DELEGATE_AMOUNT,
  PROVISIONING_POOL_ADDR,
  TRANSACTION_STATUS,
  DOCKERTAG,
  DOCKERIMAGE,
  NETNAME,
  NETDOMAIN,
  agBinary,
  FAUCET_KEYNAME,
  podname,
  RPC_PORT,
  agoricHome,
  chainId,
  namespace,
  FAKE,
} from './constants.js';
import { homeRoute as faucetAppHomeRoute } from './api/faucet-app/homeHandler.js';
import { homeRoute as publicAppHomeRoute } from './api/public-app/homeHandler.js';

import { makeSubscriptionKit } from '@agoric/notifier';

const { details: X } = globalThis.assert;

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

assert(agoricHome, X`AGORIC_HOME not set`);
assert(chainId, X`CHAIN_ID not set`);

/**
 * @param {string} relativeUrl
 * @returns {Promise<any>}
 */

const getMetricsRequest = async relativeUrl => {
  const url = new URL('http://localhost:26661/metrics');
  const response = await fetch(url.href);
  return response.text();
};

// eslint-disable-next-line no-unused-vars
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

publicapp.get('/', publicAppHomeRoute);

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

publicapp.get('/docker-compose.yml', async (req, res) => {
  let dockerImage = await getDockerImage(namespace, podname, FAKE);
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
    ${agBinary} tx swingset provision-one faucet_provision ${address} ${clientType} \
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



// Faucet worker.

const constructAmountToSend = (amount, denoms) => denoms.map(denom => `${amount}${denom}`).join(',');



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


faucetapp.get('/', faucetAppHomeRoute);

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
