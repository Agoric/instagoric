// @ts-check
import { fs } from 'zx';
export const AG0_MODE = (process.env.AG0_MODE || 'false') === 'true';

export const COMMANDS = {
  'SEND_BLD/IBC': 'send_bld_ibc',
  SEND_AND_PROVISION_IST: 'send_ist_and_provision',
  FUND_PROV_POOL: 'fund_provision_pool',
  CUSTOM_DENOMS_LIST: 'custom_denoms_list',
};

export const BASE_AMOUNT = '25000000';

export const CLIENT_AMOUNT =
  process.env.CLIENT_AMOUNT || '25000000uist,25000000ibc/toyusdc';
export const DELEGATE_AMOUNT =
  process.env.DELEGATE_AMOUNT ||
  '75000000ubld,25000000ibc/toyatom,25000000ibc/toyellie,25000000ibc/toyusdc,25000000ibc/toyollie';

export const PROVISIONING_POOL_ADDR =
  'agoric1megzytg65cyrgzs6fvzxgrcqvwwl7ugpt62346';

export const TRANSACTION_STATUS = {
  FAILED: 1000,
  NOT_FOUND: 1001,
  SUCCESSFUL: 1002,
};

export const DOCKERTAG = process.env.DOCKERTAG; // Optional.
export const DOCKERIMAGE = process.env.DOCKERIMAGE; // Optional.

export const NETNAME = process.env.NETNAME || 'devnet';
export const NETDOMAIN = process.env.NETDOMAIN || '.agoric.net';
export const agBinary = AG0_MODE ? 'ag0' : 'agd';

export const FAUCET_KEYNAME =
  process.env.FAUCET_KEYNAME || process.env.WHALE_KEYNAME || 'self';

export const podname = process.env.POD_NAME || 'validator-primary';
export const INCLUDE_SEED = process.env.SEED_ENABLE || 'yes';
export const NODE_ID =
  process.env.NODE_ID || 'fb86a0993c694c981a28fa1ebd1fd692f345348b';
export const RPC_PORT = 26657;
export const agoricHome = process.env.AGORIC_HOME;
export const chainId = process.env.CHAIN_ID;

export const namespace =
  process.env.NAMESPACE ||
  fs.readFileSync('/var/run/secrets/kubernetes.io/serviceaccount/namespace', {
    encoding: 'utf8',
    flag: 'r',
  });

export const FAKE = process.env.FAKE || process.argv[2] === '--fake';

let revision;
if (FAKE) {
  revision = 'fake_revision';
} else {
  revision =
    process.env.AG0_MODE === 'true'
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
}

export { revision };
