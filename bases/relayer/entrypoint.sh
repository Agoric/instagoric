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
PORT=transfer
RELAYER_MNEMONIC=${RELAYER_MNEMONIC:-"talk prepare desk time attract morning grow arrange buddy appear spring bring genuine deer any mercy lizard wife local runway tennis erode auction square"}
SDK_ROOT_PATH=/usr/src/agoric-sdk

curl "https://raw.githubusercontent.com/cosmos/chain-registry/refs/heads/master/testnets/$EXTERNAL_CHAIN_NAME/chain.json" \
 --output "$EXTERNAL_CHAIN_DATA_FILE" 2>/dev/null

EXTERNAL_CHAIN_ADDRESS_PREFIX=$(jq --raw-output .bech32_prefix < "$EXTERNAL_CHAIN_DATA_FILE")
EXTERNAL_CHAIN_GAS_DENOM=$(jq --raw-output .fees.fee_tokens[0].denom < "$EXTERNAL_CHAIN_DATA_FILE")
EXTERNAL_CHAIN_ID=$(jq --raw-output .chain_id < "$EXTERNAL_CHAIN_DATA_FILE")
EXTERNAL_CHAIN_RPC=$(jq --raw-output .apis.rpc[0].address < "$EXTERNAL_CHAIN_DATA_FILE")

INTERNAL_CHAIN_ADDRESS_PREFIX=${INTERNAL_CHAIN_ADDRESS_PREFIX:-agoric}
INTERNAL_CHAIN_GAS_DENOM=${INTERNAL_CHAIN_GAS_DENOM:-ubld}

rm "$EXTERNAL_CHAIN_DATA_FILE"

cp "$DIRECTORY_PATH/confio-relayer.patch" "$SDK_ROOT_PATH/patches/@confio+relayer+0.11.3.patch"
yarn --cwd="$SDK_ROOT_PATH" patch-package

mkdir --parents "$HOME_PATH"
cp \
 "$DIRECTORY_PATH/app.yaml" \
 "$DIRECTORY_PATH/registry.yaml" \
 "$HOME_PATH"

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

# TODO: Add faucet flows
# Check address using agoric ibc-setup keys list --home="$HOME_PATH"
sleep infinity
# agoric ibc-setup ics20 --home="$HOME_PATH"
# agoric ibc-relayer start --home="$HOME_PATH" --log-level=debug --poll=10
