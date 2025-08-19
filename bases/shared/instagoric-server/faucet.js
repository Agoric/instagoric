// @ts-check

import { publicapp } from './app.js';
import { COMMANDS, DELEGATE_AMOUNT } from './constants.js';
import {
  getFaucetAccountAddress,
  getFaucetAccountBalances,
  getTransactionStatus,
  sendFunds,
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

  const command = /** @type {string} */ (
    searchParams.command || COMMANDS['SEND_BLD/IBC']
  );

  switch (command) {
    case COMMANDS['SEND_BLD/IBC']: {
      [exitCode, txHash] = await sendFunds(address, DELEGATE_AMOUNT);
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
