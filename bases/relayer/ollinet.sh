#! /bin/bash

set -o errexit -o errtrace -o nounset

DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
NETWORK_CONFIG_URL="https://ollinet.agoric.net/network-config"
SCRIPT_NAME="$(basename "$0")"

network_config="$(curl --fail --location --silent "$NETWORK_CONFIG_URL")"

CHAIN_ID="$(echo "$network_config" | jq --raw-output '.chainName')" \
    CHAIN_NAME="${SCRIPT_NAME%.sh}" \
    CHAIN_RPC="$(echo "$network_config" | jq --raw-output '.rpcAddrs[0]')" \
    /bin/bash "$DIRECTORY_PATH/add-local-chain.sh"
