#!/bin/bash

set -o errexit -o errtrace

if [ -z "$EXTERNAL_CHAIN_NAME" ]
then
    echo "EXTERNAL_CHAIN_NAME not provided"
    sleep infinity
fi

set -o nounset

DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
EXTERNAL_CHAIN_NAME=${EXTERNAL_CHAIN_NAME:-osmosistestnet}
EXTERNAL_KEY_NAME=${EXTERNAL_KEY_NAME:-"My Wallet"}
HOME_PATH="$HOME/.relayer"
INTERNAL_CHAIN_NAME=agoric
INTERNAL_CHAIN_RPC="http://$RPCNODES_SERVICE_HOST:$RPCNODES_SERVICE_PORT"
INTERNAL_KEY_NAME=${INTERNAL_KEY_NAME:-"My Wallet"}
RELAYER_BINARY_EXPECTED_MD5_HASH="34496ca949e0e8fd7d9ab0514554b0a6"
RELAYER_MNEMONIC=${RELAYER_MNEMONIC:-"orbit bench unit task food shock brand bracket domain regular warfare company announce wheel grape trust sphere boy doctor half guard ritual three ecology"}

INTERNAL_CHAIN_ADDRESS_PREFIX=${INTERNAL_CHAIN_ADDRESS_PREFIX:-agoric}
INTERNAL_CHAIN_GAS_DENOM=${INTERNAL_CHAIN_GAS_DENOM:-ubld}

add_chains() {
    TESTNET_FLAG=""
    if [ "$IS_EXTERNAL_CHAIN_TESTNET" == "true" ]
    then
        TESTNET_FLAG="--testnet"
    fi

    relayer chains add "$EXTERNAL_CHAIN_NAME" \
     --home "$HOME_PATH" "$TESTNET_FLAG"
    relayer chains add "$INTERNAL_CHAIN_NAME" \
     --file "$HOME_PATH/internal-chain-config.json" --home "$HOME_PATH"
}

add_keys() {
    relayer keys restore "$EXTERNAL_CHAIN_NAME" "$EXTERNAL_KEY_NAME" "$RELAYER_MNEMONIC" \
     --home "$HOME_PATH"
    relayer keys restore "$INTERNAL_CHAIN_NAME" "$INTERNAL_KEY_NAME" "$RELAYER_MNEMONIC" \
     --home "$HOME_PATH"

    relayer keys use "$EXTERNAL_CHAIN_NAME" "$EXTERNAL_KEY_NAME"
    relayer keys use "$INTERNAL_CHAIN_NAME" "$INTERNAL_KEY_NAME"
}

add_path() {
    EXTERNAL_CHAIN_ID=$(
        relayer chains show "$EXTERNAL_CHAIN_NAME" \
         --home "$HOME_PATH" --json | \
        jq --raw-output '.value."chain-id"'
    )
    PATH_NAME="$INTERNAL_CHAIN_NAME-$EXTERNAL_CHAIN_NAME"

    relayer paths new "$CHAIN_ID" "$EXTERNAL_CHAIN_ID" "$PATH_NAME" \
     --home "$HOME_PATH"
    relayer transact link "$PATH_NAME" \
     --home "$HOME_PATH" --override
}

fetch_binary() {
    RELAYER_PATH="/bin/relayer"

    curl "https://storage.googleapis.com/simulationlab_cloudbuild/rly" \
     --output "$RELAYER_PATH"
    chmod +x "$RELAYER_PATH"

    RELAYER_BINARY_RECEIVED_MD5_HASH=$(md5sum "$RELAYER_PATH" --binary | awk '{ print $1 }')

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

initiate_configuration() {
    relayer config init --home "$HOME_PATH"
}

move_config_files() {
    cp "$DIRECTORY_PATH/internal-chain-config.json" "$HOME_PATH"
}

replace_placeholders_in_config_files() {
    sed "$HOME_PATH/internal-chain-config.json" \
     --expression="s/\\\$INTERNAL_CHAIN_ADDRESS_PREFIX/${INTERNAL_CHAIN_ADDRESS_PREFIX}/g" \
     --expression="s/\\\$INTERNAL_CHAIN_GAS_DENOM/${INTERNAL_CHAIN_GAS_DENOM}/g" \
     --expression="s/\\\$INTERNAL_CHAIN_ID/${CHAIN_ID}/g" \
     --expression="s|\\\$INTERNAL_CHAIN_RPC|${INTERNAL_CHAIN_RPC}|g" \
     --in-place \
     --regexp-extended
}

start_relayer() {
    EXTERNAL_CLIENT_ID=$(
        relayer config show \
         --home "$HOME_PATH" --json | \
        jq --raw-output '.paths."'"$PATH_NAME"'".dst."client-id"'
    )
    EXTERNAL_CONNECTION_ID=$(
        relayer config show \
         --home "$HOME_PATH" --json | \
        jq --raw-output '.paths."'"$PATH_NAME"'".dst."connection-id"'
    )
    INTERNAL_CLIENT_ID=$(
        relayer config show \
         --home "$HOME_PATH" --json | \
        jq --raw-output '.paths."'"$PATH_NAME"'".src."client-id"'
    )
    INTERNAL_CONNECTION_ID=$(
        relayer config show \
         --home "$HOME_PATH" --json | \
        jq --raw-output '.paths."'"$PATH_NAME"'".src."connection-id"'
    )

    EXTERNAL_CHANNEL_ID=$(
        relayer query connection-channels "$EXTERNAL_CHAIN_NAME" "$EXTERNAL_CONNECTION_ID" \
         --home "$HOME_PATH" --output json | \
        jq --raw-output '.channel_id'
    )
    INTERNAL_CHANNEL_ID=$(
        relayer query connection-channels "$INTERNAL_CHAIN_NAME" "$INTERNAL_CONNECTION_ID" \
         --home "$HOME_PATH" --output json | \
        jq --raw-output '.channel_id'
    )

    echo "External chain client ID: $EXTERNAL_CLIENT_ID, External chain channel ID: $EXTERNAL_CHANNEL_ID, External chain connection ID: $EXTERNAL_CONNECTION_ID"
    echo "Internal chain client ID: $INTERNAL_CLIENT_ID, Internal chain channel ID: $INTERNAL_CHANNEL_ID, Internal chain connection ID: $INTERNAL_CONNECTION_ID"

    relayer start --log-level debug
}

install_packages
fetch_binary
initiate_configuration
move_config_files
replace_placeholders_in_config_files
add_chains
add_keys
add_path
start_relayer
