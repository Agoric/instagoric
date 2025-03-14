#!/bin/bash

set -o errexit -o errtrace -o xtrace

if test -z "$EXTERNAL_CHAIN_NAME"; then
    echo "EXTERNAL_CHAIN_NAME not provided"
    sleep infinity
fi

CONFIG_FILE_PATH="$RELAYER_HOME/config/config.yaml"
DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
EXTERNAL_CHAIN_NAME=${EXTERNAL_CHAIN_NAME:-"osmosistestnet"}
EXTERNAL_KEY_NAME=${EXTERNAL_KEY_NAME:-"My Wallet"}
INTERNAL_CHAIN_ADDRESS_PREFIX=${INTERNAL_CHAIN_ADDRESS_PREFIX:-"agoric"}
INTERNAL_CHAIN_CONFIG_FILE_NAME="internal-chain-config.json"
INTERNAL_CHAIN_GAS_DENOM=${INTERNAL_CHAIN_GAS_DENOM:-"ubld"}
INTERNAL_CHAIN_NAME="agoric"
INTERNAL_CHAIN_RPC="http://$RPCNODES_SERVICE_HOST:$RPCNODES_SERVICE_PORT"
INTERNAL_KEY_NAME=${INTERNAL_KEY_NAME:-"My Wallet"}
RELAYER_BINARY_EXPECTED_MD5_HASH="34496ca949e0e8fd7d9ab0514554b0a6"
RELAYER_MNEMONIC=${RELAYER_MNEMONIC:-"orbit bench unit task food shock brand bracket domain regular warfare company announce wheel grape trust sphere boy doctor half guard ritual three ecology"}
RELAYER_PATH="/bin/relayer"

INTERNAL_CHAIN_CONFIG_FILE_PATH="$RELAYER_HOME/$INTERNAL_CHAIN_CONFIG_FILE_NAME"
PATH_NAME="$INTERNAL_CHAIN_NAME-$EXTERNAL_CHAIN_NAME"

add_chains() {
    if ! relayer chains show "$EXTERNAL_CHAIN_NAME" --home "$RELAYER_HOME" >/dev/null 2>&1; then
        TESTNET_FLAG=""
        if test -z "$IS_EXTERNAL_CHAIN_TESTNET"; then
            if [[ "$EXTERNAL_CHAIN_NAME" =~ ^.*testnet$ ]]; then
                TESTNET_FLAG="--testnet"
            fi
        else
            if test "$IS_EXTERNAL_CHAIN_TESTNET" == "true"; then
                TESTNET_FLAG="--testnet"
            fi
        fi
        relayer chains add "$EXTERNAL_CHAIN_NAME" --home "$RELAYER_HOME" "$TESTNET_FLAG"
    fi

    if ! relayer chains show "$INTERNAL_CHAIN_NAME" --home "$RELAYER_HOME" >/dev/null 2>&1; then
        relayer chains add "$INTERNAL_CHAIN_NAME" --file "$INTERNAL_CHAIN_CONFIG_FILE_PATH" --home "$RELAYER_HOME"
    fi
}

add_keys() {
    if ! relayer keys show "$EXTERNAL_CHAIN_NAME" "$EXTERNAL_KEY_NAME" --home "$RELAYER_HOME" >/dev/null 2>&1; then
        relayer keys restore "$EXTERNAL_CHAIN_NAME" "$EXTERNAL_KEY_NAME" "$RELAYER_MNEMONIC" \
            --home "$RELAYER_HOME"
    fi

    if ! relayer keys show "$INTERNAL_CHAIN_NAME" "$INTERNAL_KEY_NAME" --home "$RELAYER_HOME" >/dev/null 2>&1; then
        relayer keys restore "$INTERNAL_CHAIN_NAME" "$INTERNAL_KEY_NAME" "$RELAYER_MNEMONIC" \
            --home "$RELAYER_HOME"
    fi

    if ! test "$(relayer config show --home "$RELAYER_HOME" --json | jq --raw-output ".chains.$EXTERNAL_CHAIN_NAME.value.key")" == "$EXTERNAL_KEY_NAME"; then
        relayer keys use "$EXTERNAL_CHAIN_NAME" "$EXTERNAL_KEY_NAME" --home "$RELAYER_HOME"
    fi

    if ! test "$(relayer config show --home "$RELAYER_HOME" --json | jq --raw-output ".chains.$INTERNAL_CHAIN_NAME.value.key")" == "$INTERNAL_KEY_NAME"; then
        relayer keys use "$INTERNAL_CHAIN_NAME" "$INTERNAL_KEY_NAME" --home "$RELAYER_HOME"
    fi
}

add_path() {
    if ! relayer paths show "$PATH_NAME" --home "$RELAYER_HOME" >/dev/null 2>&1; then
        EXTERNAL_CHAIN_ID=$(
            relayer chains show "$EXTERNAL_CHAIN_NAME" --home "$RELAYER_HOME" --json |
                jq --raw-output '.value."chain-id"'
        )
        relayer paths new "$CHAIN_ID" "$EXTERNAL_CHAIN_ID" "$PATH_NAME" --home "$RELAYER_HOME"
    fi

    if ! test "$(relayer paths show "$PATH_NAME" --home "$RELAYER_HOME" --json | jq --raw-output '.status.connection')" == "true"; then
        relayer transact link "$PATH_NAME" --home "$RELAYER_HOME" --override
    fi
}

fetch_binary() {
    curl "https://storage.googleapis.com/simulationlab_cloudbuild/rly" --output "$RELAYER_PATH"
    chmod +x "$RELAYER_PATH"

    RELAYER_BINARY_RECEIVED_MD5_HASH=$(md5sum "$RELAYER_PATH" --binary | awk '{ print $1 }')

    if test "$RELAYER_BINARY_EXPECTED_MD5_HASH" != "$RELAYER_BINARY_RECEIVED_MD5_HASH"; then
        echo "Expected hash: $RELAYER_BINARY_EXPECTED_MD5_HASH, Received hash: $RELAYER_BINARY_RECEIVED_MD5_HASH"
        exit 1
    fi
}

install_packages() {
    apt-get update >/dev/null 2>&1
    apt-get install curl jq --yes >/dev/null 2>&1
}

initiate_configuration() {
    if ! test -f "$CONFIG_FILE_PATH"; then
        relayer config init --home "$RELAYER_HOME"
    fi
}

main() {
    install_packages
    fetch_binary
    initiate_configuration
    move_config_files
    replace_placeholders_in_config_files
    add_chains
    add_keys
    add_path
    start_relayer
}

move_config_files() {
    cp "$DIRECTORY_PATH/$INTERNAL_CHAIN_CONFIG_FILE_NAME" "$RELAYER_HOME"
}

replace_placeholders_in_config_files() {
    sed "$INTERNAL_CHAIN_CONFIG_FILE_PATH" \
        --expression "s|\$INTERNAL_CHAIN_ADDRESS_PREFIX|$INTERNAL_CHAIN_ADDRESS_PREFIX|" \
        --expression "s|\$INTERNAL_CHAIN_GAS_DENOM|$INTERNAL_CHAIN_GAS_DENOM|" \
        --expression "s|\$INTERNAL_CHAIN_ID|$CHAIN_ID|" \
        --expression "s|\$INTERNAL_CHAIN_RPC|$INTERNAL_CHAIN_RPC|" \
        --in-place
}

start_relayer() {
    EXTERNAL_CLIENT_ID=$(
        relayer config show \
            --home "$RELAYER_HOME" --json |
            jq --raw-output '.paths."'"$PATH_NAME"'".dst."client-id"'
    )
    EXTERNAL_CONNECTION_ID=$(
        relayer config show \
            --home "$RELAYER_HOME" --json |
            jq --raw-output '.paths."'"$PATH_NAME"'".dst."connection-id"'
    )
    INTERNAL_CLIENT_ID=$(
        relayer config show \
            --home "$RELAYER_HOME" --json |
            jq --raw-output '.paths."'"$PATH_NAME"'".src."client-id"'
    )
    INTERNAL_CONNECTION_ID=$(
        relayer config show \
            --home "$RELAYER_HOME" --json |
            jq --raw-output '.paths."'"$PATH_NAME"'".src."connection-id"'
    )

    EXTERNAL_CHANNEL_ID=$(
        relayer query connection-channels "$EXTERNAL_CHAIN_NAME" "$EXTERNAL_CONNECTION_ID" \
            --home "$RELAYER_HOME" --output json |
            jq --raw-output '.channel_id'
    )
    INTERNAL_CHANNEL_ID=$(
        relayer query connection-channels "$INTERNAL_CHAIN_NAME" "$INTERNAL_CONNECTION_ID" \
            --home "$RELAYER_HOME" --output json |
            jq --raw-output '.channel_id'
    )

    echo "External chain client ID: $EXTERNAL_CLIENT_ID, External chain channel ID: $EXTERNAL_CHANNEL_ID, External chain connection ID: $EXTERNAL_CONNECTION_ID"
    echo "Internal chain client ID: $INTERNAL_CLIENT_ID, Internal chain channel ID: $INTERNAL_CHANNEL_ID, Internal chain connection ID: $INTERNAL_CONNECTION_ID"

    relayer start --home "$RELAYER_HOME" --log-format "json" --log-level "debug"
}

main
