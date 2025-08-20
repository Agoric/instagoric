// @ts-check

import { $, nothrow } from 'zx';

import {
  AGORIC_HOME,
  CHAIN_ID,
  FAUCET_KEYNAME,
  RPC_PORT,
  TRANSACTION_STATUS,
} from './constants.js';

/** @type {string} */
let FAUCET_ADDRESS;

/**
 * @param {string} amount
 * @param {Array<string>} denoms
 */
export const constructAmountToSend = (amount, denoms) =>
  denoms.map(denom => `${amount}${denom}`).join(',');

export const getFaucetAccountAddress = async () => {
  if (!FAUCET_ADDRESS) {
    const { stdout } =
      await $`agd keys show "${FAUCET_KEYNAME}" --address --home "${AGORIC_HOME}" --keyring-backend "test"`;
    FAUCET_ADDRESS = stdout.trim();
  }

  return FAUCET_ADDRESS;
};

export const getFaucetAccountBalances = async () => {
  // Not handling pagination as it is used for testing. Limit 100 shoud suffice
  const { stdout } =
    await $`agd query bank balances "${await getFaucetAccountAddress()}" --home "${AGORIC_HOME}" --limit "100" --output "json"`;

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
    $`agd query tx ${txHash} --chain-id "${CHAIN_ID}" --home "${AGORIC_HOME}" --node "http://localhost:${RPC_PORT}" --output "json"`,
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
