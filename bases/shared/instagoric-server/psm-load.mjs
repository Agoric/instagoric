#!/usr/bin/env zx
// @ts-check
import { $, sleep } from 'zx';

// TODO: fetch at runtime
const psmGov = {
  WantStableFee: 0.01,
  GiveStableFee: 0.03,
};

const networks = {
  local: { rpc: 'http://0.0.0.0:26657', chainId: 'agoric' },
  xnet: { rpc: 'https://xnet.rpc.agoric.net:443', chainId: 'agoricxnet-13' },
};

const { AGORIC_D, PSM_TOOL } = process.env;

const psmTool = PSM_TOOL || 'psm-tool';
const agd = AGORIC_D || `agd`;

const psmInstance = (await $`${psmTool} --contract`.quiet()).stdout.trim();
// console.debug(psmInstance);

const ensureAccount = async () => {
  const keys = JSON.parse(
    (await $`${agd} keys list --output json`.quiet()).stdout,
  );
  const key = keys.find(({ type }) => type === 'local');
  if (!key) {
    throw Error('no local key in keyring. TODO: agd keys add ...');
  }
  // console.debug({ key });
  return key;
};

const account = await ensureAccount();

const getStatus = async () => {
  const txt = (await $`${psmTool} --wallet ${account.address}`.quiet()).stdout;
  // undo console.log() abbreviation of keys, JSON.string() of parts
  const json = txt.replace(/(balances|offers):/gm, '"$1":').replace(/'/gm, '');
  return JSON.parse(json);
};
// console.log(await getStatus());

const trade = async (
  boardId,
  method,
  qty,
  keyName,
  { rpc: node, chainId, blockTime = 6 } = networks.xnet,
) => {
  const feePct =
    method === 'wantStable' ? psmGov.WantStableFee : psmGov.GiveStableFee;
  const out = $`${psmTool} --boardId ${boardId} --${method} ${qty} --feePct ${
    feePct + 0.001
  }`.quiet();
  const spendAction = JSON.parse((await out).stdout);
  const {
    data: {
      meta: { creationStamp },
    },
  } = spendAction;
  const target = new Date(creationStamp).toISOString();
  console.info(
    `${target}: PSM (${boardId}) trade: ${method} ${qty} (${feePct}% fee)`,
  );

  console.info('tx swingset wallet-action ', { chainId, keyName });
  const submit = $`${agd} --from=${keyName} tx swingset wallet-action --allow-spend ${JSON.stringify(
    spendAction,
  )}  --node=${node} --chain-id=${chainId} -o json -y
  `;
  submit.quiet();
  const { txhash } = JSON.parse((await submit).stdout);
  console.info('txhash', txhash, 'for offer at', target);

  let elapsed = 0;
  for (;;) {
    const walletStatus = await getStatus();
    const found = walletStatus.offers.find(([dateTime]) => dateTime === target);
    console.info(JSON.stringify(found || [target, null]));
    const [dateTime, offerStatus] = found || [];
    switch (offerStatus) {
      case 'accept':
        return { offer: found, elapsed, chainId, txhash };
      case 'rejected':
        throw Error(`${method} offer at ${dateTime} rejected`);
      default:
        await sleep(blockTime * 1000);
        elapsed += blockTime;
    }
  }
};

const manyTrades = async (todo, simultaneous) => {
  let done = 0;
  let inProgress = new Set();

  const go = async () => {
    if (done + inProgress.size >= todo) return;

    const method = done < 3 || done % 2 === 0 ? 'wantStable' : 'giveStable';
    const qty = 4 + (done % 12);
    const job = trade(psmInstance, method, qty, account.name, networks.local);
    inProgress.add(job);

    job
      .then(result => {
        done += 1;
        console.info(done, 'of', todo, ':', JSON.stringify(result));
        inProgress.delete(job);
      })
      .catch(err => {
        // TODO: which job?
        console.error('job failed:', err);
      })
      .finally(go);
    return Promise.all([
      job,
      (async () => {
        await sleep(500); // half a sec between jobs
        if (inProgress.size < simultaneous) {
          return go();
        }
      })(),
    ]);
  };
  return go();
};

// console.log(process.argv);
const [_node, _script, qtyS, simS] = process.argv;
const [qty, sim] = [Number(qtyS), Number(simS)];

await manyTrades(qty, sim);
