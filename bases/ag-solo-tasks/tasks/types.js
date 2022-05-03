// @ts-check
import '@agoric/zoe/exported.js';
import '@agoric/vats/exported.js';
import '@agoric/run-protocol/exported.js';

export {};

/**
 * @typedef {{
 *   zoe: ERef<ZoeService>,
 *   board: ERef<Board>,
 *   scratch: ERef<Store<string, unknown>>,
 *   agoricNames: ERef<NameHub>,
 * }} Home
 *
 * @typedef {Object} DeployPowers The special powers that `agoric deploy` gives us
 * @property {(path: string) => Promise<Bundle>} bundleSource
 * @property {(path: string) => string} pathResolve
 *
 * @typedef {{ moduleFormat: string}} Bundle
 */
