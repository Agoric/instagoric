import {
  agBinary,
  RPC_PORT,
  agoricHome,
  chainId,
  TRANSACTION_STATUS,
  FAUCET_KEYNAME,
} from './constants.js';
import { $, fs } from 'zx';
import https from 'https';
export const getDenoms = async () => {
  // Not handling pagination as it is used for testing. Limit 100 shoud suffice

  const result = await $`${agBinary} query bank total --limit=100 -o json`;
  const output = JSON.parse(result.stdout.trim());
  return output.supply.map(element => element.denom);
};

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

export async function getDockerImage(namespace, podname, FAKE) {
  if (FAKE) {
    return 'asdf:unknown';
  } else {
    const statefulSet = await makeKubernetesRequest(
      `/apis/apps/v1/namespaces/${namespace}/statefulsets/${podname}`,
    );
    return statefulSet.spec.template.spec.containers[0].image;
  }
}
