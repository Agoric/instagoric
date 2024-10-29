import { fs } from 'zx';

export const BASE_AMOUNT = '25000000';

export const CLIENT_AMOUNT =
  process.env.CLIENT_AMOUNT || '25000000uist,25000000ibc/toyusdc';

export const DELEGATE_AMOUNT =
  process.env.DELEGATE_AMOUNT ||
  '75000000ubld,25000000ibc/toyatom,25000000ibc/toyellie,25000000ibc/toyusdc,25000000ibc/toyollie';

export const COMMANDS = {
  'SEND_BLD/IBC': 'send_bld_ibc',
  SEND_AND_PROVISION_IST: 'send_ist_and_provision',
  FUND_PROV_POOL: 'fund_provision_pool',
  CUSTOM_DENOMS_LIST: 'custom_denoms_list',
};

export const PROVISIONING_POOL_ADDR =
  'agoric1megzytg65cyrgzs6fvzxgrcqvwwl7ugpt62346';

export const DOCKERTAG = process.env.DOCKERTAG;
export const DOCKERIMAGE = process.env.DOCKERIMAGE;

export const FAUCET_KEYNAME =
  process.env.FAUCET_KEYNAME || process.env.WHALE_KEYNAME || 'self';

export const AG0_MODE = (process.env.AG0_MODE || 'false') === 'true';
export const agBinary = AG0_MODE ? 'ag0' : 'agd';

export const NETNAME = process.env.NETNAME || 'devnet';
export const NETDOMAIN = process.env.NETDOMAIN || '.agoric.net';

export const RPC_PORT = 26657;

export const TRANSACTION_STATUS = {
  FAILED: 1000,
  NOT_FOUND: 1001,
  SUCCESSFUL: 1002,
};

export const FAKE = process.env.FAKE || process.argv[2] === '--fake';
export const podname = process.env.POD_NAME || 'validator-primary';
export const namespace =
  process.env.NAMESPACE ||
  fs.readFileSync('/var/run/secrets/kubernetes.io/serviceaccount/namespace', {
    encoding: 'utf8',
    flag: 'r',
  });
export const INCLUDE_SEED = process.env.SEED_ENABLE || 'yes';
export const NODE_ID =
  process.env.NODE_ID || 'fb86a0993c694c981a28fa1ebd1fd692f345348b';

const { details: X } = globalThis.assert;

export const agoricHome = process.env.AGORIC_HOME;
assert(agoricHome, X`AGORIC_HOME not set`);

export const chainId = process.env.CHAIN_ID;
assert(chainId, X`CHAIN_ID not set`);

let revisionValue;

if (FAKE) {
  revisionValue = 'fake_revision';
} else {
  revisionValue =
    AG0_MODE === 'true'
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

export const revision = revisionValue;
