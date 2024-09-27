#!/bin/bash

set -o errexit -o errtrace

if [ -z "$EXTERNAL_CHAIN_NAME" ]
then
    echo "EXTERNAL_CHAIN_NAME not provided"
    sleep infinity
fi

set -o nounset

DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
EXTERNAL_CHAIN_DATA_FILE=external_chain.json
HOME_PATH="$HOME/.relayer"
INTERNAL_CHAIN_NAME=agoric
INTERNAL_CHAIN_RPC="http://$RPCNODES_SERVICE_HOST:$RPCNODES_SERVICE_PORT"
POLL_INTERVAL=10
PORT=transfer
RELAYER_MNEMONIC=${RELAYER_MNEMONIC:-"talk prepare desk time attract morning grow arrange buddy appear spring bring genuine deer any mercy lizard wife local runway tennis erode auction square"}
SDK_ROOT_PATH=/usr/src/agoric-sdk

INTERNAL_CHAIN_ADDRESS_PREFIX=${INTERNAL_CHAIN_ADDRESS_PREFIX:-agoric}
INTERNAL_CHAIN_GAS_DENOM=${INTERNAL_CHAIN_GAS_DENOM:-ubld}

cleanup() {
    rm "$EXTERNAL_CHAIN_DATA_FILE"
}

ensure_balance_in_external_chain_address() {
    EXTERNAL_CHAIN_ADDRESS=$(
        echo "$ADDRESSES" | sed -n "s/.*${EXTERNAL_CHAIN_NAME}: \(${EXTERNAL_CHAIN_ADDRESS_PREFIX}[^\ ]*\).*/\1/p"
    )

    EXTERNAL_CHAIN_ADDRESS_BALANCE=$(
        curl "${EXTERNAL_CHAIN_REST}/cosmos/bank/v1beta1/balances/$EXTERNAL_CHAIN_ADDRESS" | \
        jq --arg denom "$EXTERNAL_CHAIN_GAS_DENOM" '.balances[] | select(.denom == $denom) | .amount | tonumber'
    )

    while true
    do
        if [ -z "$EXTERNAL_CHAIN_ADDRESS_BALANCE" ] || [ "$EXTERNAL_CHAIN_ADDRESS_BALANCE" -eq 0 ]
        then
            echo "Address $EXTERNAL_CHAIN_ADDRESS has no funds yet. Retrying again after $POLL_INTERVAL seconds"
            sleep $POLL_INTERVAL
        else
            echo "Address $EXTERNAL_CHAIN_ADDRESS has now $EXTERNAL_CHAIN_ADDRESS_BALANCE $EXTERNAL_CHAIN_GAS_DENOM"
            break
        fi
    done
}

extract_external_chain_data() {
    EXTERNAL_CHAIN_ADDRESS_PREFIX=$(jq --raw-output .bech32_prefix < "$EXTERNAL_CHAIN_DATA_FILE")
    EXTERNAL_CHAIN_GAS_DENOM=$(jq --raw-output .fees.fee_tokens[0].denom < "$EXTERNAL_CHAIN_DATA_FILE")
    EXTERNAL_CHAIN_ID=$(jq --raw-output .chain_id < "$EXTERNAL_CHAIN_DATA_FILE")
    EXTERNAL_CHAIN_REST="$(jq --raw-output .apis.rest[0].address < "$EXTERNAL_CHAIN_DATA_FILE")"
    EXTERNAL_CHAIN_RPC=$(jq --raw-output .apis.rpc[0].address < "$EXTERNAL_CHAIN_DATA_FILE")

    EXTERNAL_CHAIN_REST="${EXTERNAL_CHAIN_REST%/}"
    EXTERNAL_CHAIN_RPC="${EXTERNAL_CHAIN_RPC%/}"
}

get_external_chain_specs() {
    curl "https://raw.githubusercontent.com/cosmos/chain-registry/refs/heads/master/testnets/$EXTERNAL_CHAIN_NAME/chain.json" \
     --output "$EXTERNAL_CHAIN_DATA_FILE" 2>/dev/null
}

move_config_files() {
    mkdir --parents "$HOME_PATH"
    cp \
     "$DIRECTORY_PATH/app.yaml" \
     "$DIRECTORY_PATH/registry.yaml" \
     "$HOME_PATH"
}

patch_relayer() {
    cp "$DIRECTORY_PATH/confio-relayer.patch" "$SDK_ROOT_PATH/patches/@confio+relayer+0.11.3.patch"
    yarn --cwd="$SDK_ROOT_PATH" patch-package
}

populate_addresses() {
    ADDRESSES=$(agoric ibc-setup keys list --home="$HOME_PATH")
}

replace_placeholders_in_config_files() {
    sed "$HOME_PATH/app.yaml" \
     --expression="s/\\\$EXTERNAL_CHAIN_NAME/${EXTERNAL_CHAIN_NAME}/g" \
     --expression="s/\\\$INTERNAL_CHAIN_NAME/${INTERNAL_CHAIN_NAME}/g" \
     --expression="s/\\\$MNEMONIC/${RELAYER_MNEMONIC}/g" \
     --in-place \
     --regexp-extended

    sed "$HOME_PATH/registry.yaml" \
     --expression="s/\\\$EXTERNAL_CHAIN_ADDRESS_PREFIX/${EXTERNAL_CHAIN_ADDRESS_PREFIX}/g" \
     --expression="s/\\\$EXTERNAL_CHAIN_GAS_DENOM/${EXTERNAL_CHAIN_GAS_DENOM}/g" \
     --expression="s/\\\$EXTERNAL_CHAIN_ID/${EXTERNAL_CHAIN_ID}/g" \
     --expression="s/\\\$EXTERNAL_CHAIN_NAME/${EXTERNAL_CHAIN_NAME}/g" \
     --expression="s|\\\$EXTERNAL_CHAIN_RPC|${EXTERNAL_CHAIN_RPC}|g" \
     --expression="s/\\\$INTERNAL_CHAIN_ADDRESS_PREFIX/${INTERNAL_CHAIN_ADDRESS_PREFIX}/g" \
     --expression="s/\\\$INTERNAL_CHAIN_GAS_DENOM/${INTERNAL_CHAIN_GAS_DENOM}/g" \
     --expression="s/\\\$INTERNAL_CHAIN_ID/${CHAIN_ID}/g" \
     --expression="s/\\\$INTERNAL_CHAIN_NAME/${INTERNAL_CHAIN_NAME}/g" \
     --expression="s|\\\$INTERNAL_CHAIN_RPC|${INTERNAL_CHAIN_RPC}|g" \
     --expression="s/\\\$PORT/${PORT}/g" \
     --in-place \
     --regexp-extended
}

start_relayer() {
    agoric ibc-setup ics20 --home="$HOME_PATH"
    agoric ibc-relayer start --home="$HOME_PATH" --log-level=debug --poll="$POLL_INTERVAL"
}

patch_relayer
get_external_chain_specs
extract_external_chain_data
move_config_files
replace_placeholders_in_config_files
populate_addresses
ensure_balance_in_external_chain_address
cleanup
start_relayer
