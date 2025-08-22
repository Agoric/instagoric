// @ts-check

import { publicapp } from './app.js';
import { BASE_AMOUNT, COMMANDS, DELEGATE_AMOUNT } from './constants.js';
import {
  constructAmountToSend,
  getFaucetAccountAddress,
  getFaucetAccountBalances,
  getTransactionStatus,
  sendFundsFromFaucet,
} from './util.js';

publicapp.get('/balance', async (_, response) => {
  const [address, balance] = await Promise.all([
    getFaucetAccountAddress(),
    getFaucetAccountBalances(),
  ]);
  response.send({ address, balance });
});

publicapp.get('/transaction-status/:txhash', async (request, response) => {
  const { txhash } = request.params;
  const [transactionStatus, errorMessage] = await getTransactionStatus(txhash);
  response.send({ errorMessage, transactionStatus }).status(200);
});

publicapp.get('/send/:address', async (request, response) => {
  const { address } = request.params;
  let error = '';
  let exitCode = 0;
  let txHash = '';
  const searchParams = request.query;

  const command =
    /** @type {string} */ (searchParams.command) || COMMANDS['SEND_BLD/IBC'];
  const denoms = /** @type {string} */ (searchParams.denoms).split(',');

  switch (command) {
    case COMMANDS.CUSTOM_DENOMS_LIST: {
      [exitCode, txHash] = await sendFundsFromFaucet(
        address,
        constructAmountToSend(String(BASE_AMOUNT), denoms),
      );
      break;
    }
    case COMMANDS['SEND_BLD/IBC']: {
      [exitCode, txHash] = await sendFundsFromFaucet(address, DELEGATE_AMOUNT);
      break;
    }
    default: {
      error = `unknown command ${command}`;
      break;
    }
  }

  error
    ? response.status(500).send(error)
    : exitCode
      ? response.status(500).send(`Exit code ${exitCode}`)
      : response.send({ result: txHash });
});
