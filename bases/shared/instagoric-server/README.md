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
