#! /bin/bash

set -o nounset

DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

RPC="http://$RPCNODES_SERVICE_HOST:$RPCNODES_SERVICE_PORT" \
    /bin/bash "$DIRECTORY_PATH/local-chain-pre.sh"
