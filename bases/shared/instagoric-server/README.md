# Starting the Dev Server Locally

Before starting the development server, ensure all dependencies are installed:

```bash
yarn install
```

To start the local development server, run the following command with the necessary environment variables:

```bash
CHAIN_ID=agoriclocal yarn dev --fake
```

You can adjust and pass the following environment variables if needed:

- `AGORIC_HOME`: The directory where Agoric configuration files are stored (default: `~/.agoric`). When the `--fake` flag is used, a temporary directory is created using the `tmp` module, which serves as a temporary home for configuration and keyring files. This temporary directory is automatically discarded when the server shuts down.
- `CHAIN_ID`: The identifier of the blockchain network to connect to. This value must be set based on the specific network you're targeting (e.g., `agoriclocal` for A3P, or the relevant chain ID for testnets or mainnets).
- `AG0_MODE`: Determines which Agoric binary is used to interact with the blockchain:
  - Set to `false` (default) to use the `agd` binary, which is typically used for standard operations on the Agoric chain.
  - Set to `true` to use the `ag0` binary, if your environment or setup requires it
- `FAUCET_KEYNAME`: The wallet address used for sending tokens and provisioning.

# Working with A3P

When developing on the A3P chain, ensure that the `validator` wallet (`agoric1estsewt6jqsx77pwcxkn5ah0jqgu8rhgflwfdl`) is present in your local keyring. You can retrieve its mnemonic [from this link](https://github.com/Agoric/agoric-3-proposals/blob/93bb953db209433499db08ae563942d1bf7eeb46/packages/synthetic-chain/public/upgrade-test-scripts/run_prepare_zero.sh#L13C1-L23C2).

Since this wallet holds a significant amount of different tokens, it is sufficient for funding other wallets.

However, using this wallet for provisioning will cause errors, as it does not contain any ISTs. To resolve this, it's best to create a vault by submitting ATOMs and receiving ISTs in return. The validator wallet has plenty of ATOMs, making it ideal for this process. You can create the vault from the `dapp-inter` UI.

Once the vault is successfully created through the `dapp-inter` UI, you can use the `validator` account to provision new wallets as needed.

Once done, ensure you start the server using the `FAUCET_KEYNAME` set for this wallet:

```bash
CHAIN_ID=agoriclocal AGORIC_HOME="~/.agoric" FAUCET_KEYNAME=agoric1estsewt6jqsx77pwcxkn5ah0jqgu8rhgflwfdl yarn dev --fake
```
