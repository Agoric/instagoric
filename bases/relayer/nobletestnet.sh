#! /bin/bash

set -o errexit -o errtrace -o nounset

DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SCRIPT_NAME="$(basename "$0")"

CHAIN_ADDRESS_PREFIX="noble" \
    CHAIN_ID="grand-1" \
    CHAIN_GAS_AMOUNT="0.25" \
    CHAIN_GAS_DENOM="uusdc" \
    CHAIN_NAME="${SCRIPT_NAME%.sh}" \
    CHAIN_RPC="http://$NOBLE_SERVICE_SERVICE_HOST:$NOBLE_SERVICE_SERVICE_PORT_RPC" \
    COIN_TYPE="118" \
    GAS_ADJUSTMENT="1.5" \
    /bin/bash "$DIRECTORY_PATH/add-local-chain.sh"
