#! /bin/bash

set -o nounset

DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

RPC="http://$NOBLE_SERVICE_SERVICE_HOST:$NOBLE_SERVICE_SERVICE_PORT_RPC" \
    /bin/bash "$DIRECTORY_PATH/local-chain-pre.sh"
