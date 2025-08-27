// @ts-check

import { coerce as semverCoerce, lt as semverLessThan } from 'semver';
import { $, nothrow } from 'zx';

import {
  AGORIC_HOME,
  CHAIN_ID,
  FAUCET_KEYNAME,
  RPC_PORT,
  SDK_VERSIONS,
  TRANSACTION_STATUS,
} from './constants.js';

/**
 * @typedef {{
 *  build_deps: Array<string>;
 *  build_tags: string;
 *  commit: string;
 *  cosmos_sdk_version: string;
 *  go: string;
 *  name: string;
 *  server_name: string;
 *  version: string;
 * }} SDK_VERSION_OUTPUT
 */

/** @type {string} */
let AGD_SDK_VERSION;

/** @type {string} */
let FAUCET_ADDRESS;

/**
 * @param {string} amount
 * @param {Array<string>} denoms
 */
export const constructAmountToSend = (amount, denoms) =>
  denoms.map(denom => `${amount}${denom}`).join(',');

/**
 * @param {number} ms
 */
export const formatMillisecondsToDuration = ms => {
  if (ms < 1000) return `${ms} ms`;

  const seconds = Math.floor(ms / 1000);
  if (seconds < 60) return `${seconds} s`;

  return `${seconds / 60} min`;
};

export const getAgdSdkVersion = async () => {
  if (!AGD_SDK_VERSION) {
    const { stdout } = await $`agd version --long --output "json"`;
    const sdkVersion = /** @type {SDK_VERSION_OUTPUT} */ (
      JSON.parse(stdout.trim())
    ).cosmos_sdk_version;
    const coercedVersion = semverCoerce(sdkVersion);
    AGD_SDK_VERSION = !coercedVersion ? sdkVersion : coercedVersion.toString();
  }

  return AGD_SDK_VERSION;
};

export const getFaucetAccountAddress = async () => {
  if (!FAUCET_ADDRESS) {
    const { stdout } =
      await $`agd keys show "${FAUCET_KEYNAME}" --address --home "${AGORIC_HOME}" --keyring-backend "test"`;
    FAUCET_ADDRESS = stdout.trim();
  }

  return FAUCET_ADDRESS;
};

export const getFaucetAccountBalances = async () => {
  const { stdout } =
    await $`agd query bank balances "${await getFaucetAccountAddress()}" --home "${AGORIC_HOME}" ${
      semverLessThan(await getAgdSdkVersion(), SDK_VERSIONS['0.50.14'])
        ? '--limit'
        : '--page-limit'
    } "100" --output "json"`;

  /**
   * @type {{
   *  balances: Array<{amount: string; denom: string}>;
   *  pagination: { next_key: string; total: string; }
   * }}
   */
  const output = JSON.parse(stdout.trim());
  return output.balances;
};

/**
 * Returns the status of a transaction against hash `txHash`.
 * The status is one of the values from `TRANSACTION_STATUS`
 * @param {string} txHash
 * @returns {Promise<[number, string]>}
 */
export const getTransactionStatus = async txHash => {
  const txNotFoundErrorMessage = `tx (${txHash}) not found`;

  let { exitCode, stderr, stdout } = await nothrow(
    $`agd query tx ${txHash} --home "${AGORIC_HOME}" --node "http://localhost:${RPC_PORT}" --output "json"`,
  );
  exitCode = exitCode ?? 1;

  // This check is brittle as this can also happen in case
  // an invalid txhash was provided. So there is no reliable
  // distinction between the case of invalid txhash and a
  // transaction currently in the mempool. We could use search
  // endpoint but that seems overkill to cover a case where
  // only the deliberate use of invalid hash can effect the user
  if (exitCode && stderr.includes(txNotFoundErrorMessage))
    return [TRANSACTION_STATUS.NOT_FOUND, txNotFoundErrorMessage];

  const output = JSON.parse(stdout);

  const code = Number(output.code);
  return code
    ? [TRANSACTION_STATUS.FAILED, output.raw_log || txNotFoundErrorMessage]
    : [TRANSACTION_STATUS.SUCCESSFUL, ''];
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
export const sendFundsFromFaucet = async (address, amount) => {
  let { exitCode, stdout } = await nothrow($`\
    agd tx bank send ${FAUCET_KEYNAME} ${address} ${amount} \
        --broadcast-mode "sync" \
        --chain-id "${CHAIN_ID}" \
        --keyring-backend "test" \
        --keyring-dir "${AGORIC_HOME}" \
        --node "http://localhost:${RPC_PORT}" \
        --output "json" \
        --yes \
  `);
  exitCode = exitCode ?? 1;

  if (exitCode) return [exitCode, ''];
  return [exitCode, String(JSON.parse(stdout).txhash)];
};
