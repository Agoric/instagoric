#! /bin/bash

set -o errexit -o errtrace -o nounset

DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
SCRIPT_NAME="$(basename "$0")"

CHAIN_ADDRESS_PREFIX="osmo" \
    CHAIN_ID="osmo-test-5" \
    CHAIN_GAS_AMOUNT="0.1" \
    CHAIN_GAS_DENOM="uosmo" \
    CHAIN_NAME="${SCRIPT_NAME%.sh}" \
    CHAIN_RPC="https://osmosis-testnet-rpc.polkachu.com:443" \
    COIN_TYPE="118" \
    GAS_ADJUSTMENT="1.5" \
    MINIMUM_GAS_AMOUNT="400000" \
    /bin/bash "$DIRECTORY_PATH/add-local-chain.sh"
