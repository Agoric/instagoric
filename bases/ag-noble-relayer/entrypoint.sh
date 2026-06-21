#!/bin/bash

DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
INTERNAL_CHAIN_ADDRESS_PREFIX=${INTERNAL_CHAIN_ADDRESS_PREFIX:-agoric}
INTERNAL_CHAIN_GAS_DENOM=${INTERNAL_CHAIN_GAS_DENOM:-ubld}
INTERNAL_CHAIN_ID=${INTERNAL_CHAIN_ID:-agoricdev-23}
INTERNAL_CHAIN_NAME=${INTERNAL_CHAIN_NAME:-agoric}
INTERNAL_CHAIN_RPC="https://devnet.rpc.agoric.net:443"
EXTERNAL_CHAIN_ADDRESS_PREFIX=${EXTERNAL_CHAIN_ADDRESS_PREFIX:-noble}
EXTERNAL_CHAIN_GAS_DENOM=${EXTERNAL_CHAIN_GAS_DENOM:-uusdc}
EXTERNAL_CHAIN_ID=${EXTERNAL_CHAIN_ID:-grand-1}
EXTERNAL_CHAIN_NAME=${EXTERNAL_CHAIN_NAME:-nobletestnet}
EXTERNAL_CHAIN_RPC=${EXTERNAL_CHAIN_RPC:-http://noble-node.instagoric.svc.cluster.local:26657} 
RELAYER_BINARY_EXPECTED_MD5_HASH="34496ca949e0e8fd7d9ab0514554b0a6"
RELAYER_PATH="$INTERNAL_CHAIN_NAME-$EXTERNAL_CHAIN_NAME"

HOME_PATH="$HOME/.relayer"

fetch_binary() {
    BINARY_PATH="/bin/relayer"

    curl "https://storage.googleapis.com/simulationlab_cloudbuild/rly" \
     --output "$BINARY_PATH"
    chmod +x "$BINARY_PATH"

    RELAYER_BINARY_RECEIVED_MD5_HASH=$(md5sum "$BINARY_PATH" --binary | awk '{ print $1 }')

    if [ "$RELAYER_BINARY_EXPECTED_MD5_HASH" != "$RELAYER_BINARY_RECEIVED_MD5_HASH" ]
    then
        echo "Expected hash: $RELAYER_BINARY_EXPECTED_MD5_HASH, Received hash: $RELAYER_BINARY_RECEIVED_MD5_HASH"
        exit 1
    fi
}

install_packages() {
    apt-get update > /dev/null 2>&1
    apt-get install curl jq --yes > /dev/null 2>&1
}

move_config_files() {
    cp "$DIRECTORY_PATH/internal-chain-config.json" "$HOME_PATH"
    cp "$DIRECTORY_PATH/external-chain-config.json" "$HOME_PATH"
}

replace_placeholders_in_config_files() {
    sed "$HOME_PATH/internal-chain-config.json" \
     --expression="s/\\\$INTERNAL_CHAIN_ADDRESS_PREFIX/${INTERNAL_CHAIN_ADDRESS_PREFIX}/g" \
     --expression="s/\\\$INTERNAL_CHAIN_GAS_DENOM/${INTERNAL_CHAIN_GAS_DENOM}/g" \
     --expression="s/\\\$INTERNAL_CHAIN_ID/${INTERNAL_CHAIN_ID}/g" \
     --expression="s|\\\$INTERNAL_CHAIN_RPC|${INTERNAL_CHAIN_RPC}|g" \
     --in-place \
     --regexp-extended
    sed "$HOME_PATH/external-chain-config.json" \
     --expression="s/\\\$EXTERNAL_CHAIN_ADDRESS_PREFIX/${EXTERNAL_CHAIN_ADDRESS_PREFIX}/g" \
     --expression="s/\\\$EXTERNAL_CHAIN_GAS_DENOM/${EXTERNAL_CHAIN_GAS_DENOM}/g" \
     --expression="s/\\\$EXTERNAL_CHAIN_ID/${EXTERNAL_CHAIN_ID}/g" \
     --expression="s|\\\$EXTERNAL_CHAIN_RPC|${EXTERNAL_CHAIN_RPC}|g" \
     --in-place \
     --regexp-extended
}

init_relayer() {
    relayer config init
}

add_chains() {
    relayer chains add "$INTERNAL_CHAIN_NAME" --file $HOME_PATH/internal-chain-config.json
    relayer chains add "$EXTERNAL_CHAIN_NAME" --file $HOME_PATH/external-chain-config.json
}

restore_keys() {
    relayer keys restore "$INTERNAL_CHAIN_NAME" user1 "cinnamon legend sword giant master simple visit action level ancient day rubber pigeon filter garment hockey stay water crawl omit airport venture toilet oppose"
    relayer keys restore "$EXTERNAL_CHAIN_NAME" nobleuser1 "stamp later develop betray boss ranch abstract puzzle calm right bounce march orchard edge correct canal fault miracle void dutch lottery lucky observe armed"
}

use_keys() {
    relayer keys use "$INTERNAL_CHAIN_NAME" user1
    relayer keys use "$EXTERNAL_CHAIN_NAME" nobleuser1
}

add_path() {
    relayer paths new "$INTERNAL_CHAIN_ID" "$EXTERNAL_CHAIN_ID" "$RELAYER_PATH"
    relayer transact link "$RELAYER_PATH" --override
}

start_relayer() {
    relayer start
}

install_packages
fetch_binary
init_relayer
move_config_files
replace_placeholders_in_config_files
add_chains
restore_keys
use_keys
add_path
start_relayer
sleep infinity