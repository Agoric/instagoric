// @ts-check
import { $, fs, nothrow } from 'zx';
import https from 'https';
import tmp from 'tmp';
import {
  namespace,
  FAKE,
  chainId,
  NETNAME,
  NETDOMAIN,
  podname,
  NODE_ID,
  INCLUDE_SEED,
  agBinary,
  agoricHome,
  RPC_PORT,
  TRANSACTION_STATUS,
  FAUCET_KEYNAME,
  AG0_MODE,
} from './constants';

/**
 * @param {string} relativeUrl
 * @returns {Promise<any>}
 */
export const makeKubernetesRequest = async relativeUrl => {
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

export const getMetricsRequest = async () => {
  const url = new URL('http://localhost:26661/metrics');
  const response = await fetch(url.href);
  return response.text();
};

export const getNodeId = async node => {
  const response = await fetch(
    `http://${node}.${namespace}.svc.cluster.local:26657/status`,
  );
  return response.json();
};

export const getServices = async () => {
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
};

export const getNetworkConfig = async () => {
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
    'fb86a0993c694c981a28fa1ebd1fd692f345348b',
    `${NODE_ID}`,
  );
  ap.rpcAddrs = [`https://${NETNAME}.rpc${NETDOMAIN}:443`];
  ap.apiAddrs = [`https://${NETNAME}.api${NETDOMAIN}:443`];
  if (INCLUDE_SEED === 'yes') {
    ap.seeds[0] = ap.seeds[0].replace(
      'seed.instagoric.svc.cluster.local',
      svc.get('seed-ext') || `seed.${namespace}.svc.cluster.local`,
    );
  } else {
    ap.seeds = [];
  }

  return JSON.stringify(ap);
};

export const dockerComposeYaml = (
  dockerimage,
  dockertag,
  netname,
  netdomain,
) => `\
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

/**
 * Returns the status of a transaction against hash `txHash`.
 * The status is one of the values from `TRANSACTION_STATUS`
 * @param {string} txHash
 * @returns {Promise<number>}
 */
export const getTransactionStatus = async txHash => {
  let { exitCode, stderr, stdout } = await nothrow($`\
      ${agBinary} query tx ${txHash} \
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
 * @returns {Promise<void>}
 */
export const provisionAddress = async (address, clientType) => {
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

/**
 * @param {string} address
 * @param {string} clientType
 * @param {string} txHash
 * @returns {Promise<void>}
 */
export const pollForProvisioning = async (address, clientType, txHash) => {
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
export const sendFunds = async (address, amount) => {
  let { exitCode, stdout } = await nothrow($`\
      ${agBinary} tx bank send ${FAUCET_KEYNAME} ${address} ${amount} \
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

export class DataCache {
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

export const constructAmountToSend = (amount, denoms) =>
  denoms.map(denom => `${amount}${denom}`).join(',');

export const getDenoms = async () => {
  // Not handling pagination as it is used for testing. Limit 100 shoud suffice
  const result = await $`${agBinary} query bank total --limit=100 -o json`;
  const output = JSON.parse(result.stdout.trim());
  return output.supply.map(element => element.denom);
};

export const logRequest = (req, res, next) => {
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

export const getRevisionValue = async () => {
  if (FAKE) {
    return 'fake_revision';
  }

  return AG0_MODE
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
};

export const getDockerImageValue = async (namespace, podname) => {
  if (FAKE) {
    return 'asdf:unknown';
  }

  const statefulSet = await makeKubernetesRequest(
    `/apis/apps/v1/namespaces/${namespace}/statefulsets/${podname}`,
  );
  return statefulSet.spec.template.spec.containers[0].image;
};

export const createTempDir = async () => {
  return new Promise((resolve, reject) => {
    tmp.dir({ prefix: 'faucet', postfix: 'home' }, (err, path) => {
      if (err) {
        return reject(err);
      }
      resolve(path);
    });
  });
};

export const addKey = async (directory, keyName) => {
  await $`${agBinary} --home=${directory} keys --keyring-backend=test add ${keyName}`;
};
