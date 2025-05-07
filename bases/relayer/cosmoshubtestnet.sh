#! /bin/bash
# Built based on:
# https://github.com/cosmos/testnets/blob/master/interchain-security/provider/README.md

set -o errexit -o errtrace -o nounset

DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SCRIPT_NAME="$(basename "$0")"

CHAIN_ADDRESS_PREFIX="cosmos" \
    CHAIN_ID="provider" \
    CHAIN_GAS_AMOUNT="0.01" \
    CHAIN_GAS_DENOM="uatom" \
    CHAIN_NAME="${SCRIPT_NAME%.sh}" \
    CHAIN_RPC="https://rpc.provider-sentry-01.ics-testnet.polypore.xyz:443" \
    COIN_TYPE="118" \
    /bin/bash "$DIRECTORY_PATH/add-local-chain.sh"
