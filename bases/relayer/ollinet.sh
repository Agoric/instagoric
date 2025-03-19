#! /bin/bash

set -o errexit -o errtrace -o nounset

DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SCRIPT_NAME="$(basename "$0")"

CHAIN_ID="agoric-mainfork-1" \
    CHAIN_NAME="${SCRIPT_NAME%.sh}" \
    CHAIN_RPC="https://ollinet.rpc.agoric.net:443" \
    /bin/bash "$DIRECTORY_PATH/add-agoric-chain.sh"
