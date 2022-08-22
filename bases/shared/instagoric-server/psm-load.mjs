#!/usr/bin/env zx
// @ts-check
import { $, sleep } from 'zx';

// TODO: fetch at runtime
const psmGov = {
  WantStableFee: 0.01,
  GiveStableFee: 0.03,
};

const { HOME } = process.env;

const agoricSDK = `${HOME}/projects/agoric-sdk`;
const psmTool = `${agoricSDK}/packages/inter-protocol/scripts/psm-tool.js`;
const agd = `${HOME}/go/bin/agd`;

const psmInstance = await $`node --experimental-fetch ${psmTool} --contract`;
// console.debug(psmInstance);

const ensureAccount = async () => {
  const keys = JSON.parse((await $`${agd} keys list --output json`).stdout);
  const key = keys.find(({ type }) => type === 'local');
  if (!key) {
    throw Error('no local key in keyring. TODO: agd keys add ...');
  }
  // console.debug({ key });
  return key;
};

const account = await ensureAccount();

const getStatus = async () => {
  const txt = (
    await $`node --experimental-fetch ${psmTool} --wallet ${account.address}`
  ).stdout;
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
  node = 'https://xnet.rpc.agoric.net:443',
  chainId = 'agoricxnet-13',
) => {
  const feePct =
    method === 'wantStable' ? psmGov.WantStableFee : psmGov.GiveStableFee;
  // why doesn't $`...`.quiet() work?
  const out = $`node ${psmTool} --boardId ${boardId} --${method} ${qty} --feePct ${
    feePct + 0.001
  }`;
  const spendAction = JSON.parse((await out).stdout);
  console.info(`PSM (${boardId}) trade: ${method} ${qty} (${feePct}% fee)`);

  await $`${agd} --from=${keyName} tx swingset wallet-action --allow-spend ${JSON.stringify(
    spendAction,
  )}  --node=${node} --chain-id=${chainId} -y
  `;

  const blockTime = 6;
  const {
    data: {
      meta: { creationStamp },
    },
  } = spendAction;
  const target = new Date(creationStamp).toISOString();
  for (;;) {
    const walletStatus = await getStatus();
    const found = walletStatus.offers.find(([dateTime]) => dateTime === target);
    const [dateTime, offerStatus] = found || [];
    switch (offerStatus) {
      case 'accept':
        return found;
      case 'rejected':
        throw Error(`${method} offer at ${dateTime} rejected`);
      default:
        console.info(found);
        sleep((blockTime / 2) * 1000); // nyquist: observe at 2x freq
    }
  }
};

await trade(psmInstance, 'wantStable', 10, account.name);
