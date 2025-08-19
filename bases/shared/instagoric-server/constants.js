// @ts-check

export const AGORIC_HOME = process.env.AGORIC_HOME;
export const BASE_AMOUNT = 25000000;
export const CHAIN_ID = process.env.CHAIN_ID;
export const COMMANDS = {
  'SEND_BLD/IBC': 'send_bld_ibc',
  SEND_AND_PROVISION_IST: 'send_ist_and_provision',
  FUND_PROV_POOL: 'fund_provision_pool',
  CUSTOM_DENOMS_LIST: 'custom_denoms_list',
};
export const FAUCET_KEYNAME =
  process.env.FAUCET_KEYNAME ||
  process.env.WHALE_KEYNAME ||
  process.env.SELF_KEYNAME;
export const RPC_PORT = Number(process.env.RPC_PORT);
export const TRANSACTION_STATUS = {
  FAILED: 1000,
  NOT_FOUND: 1001,
  SUCCESSFUL: 1002,
};

export const DELEGATE_AMOUNT =
  process.env.DELEGATE_AMOUNT ||
  `${BASE_AMOUNT * 3}${
    process.env.BLD_DENOM
  },${BASE_AMOUNT}ibc/toyatom,${BASE_AMOUNT}ibc/toyellie,${BASE_AMOUNT}ibc/toyusdc,${BASE_AMOUNT}ibc/toyollie`;
