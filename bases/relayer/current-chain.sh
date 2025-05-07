#! /bin/bash

set -o errexit -o errtrace -o nounset

DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SCRIPT_NAME="$(basename "$0")"

CHAIN_NAME="${SCRIPT_NAME%.sh}" \
  CHAIN_RPC="http://$RPCNODES_SERVICE_HOST:$RPCNODES_SERVICE_PORT" \
  /bin/bash "$DIRECTORY_PATH/add-local-chain.sh"
