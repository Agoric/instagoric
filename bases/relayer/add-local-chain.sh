#! /bin/bash

set -o errexit -o errtrace -o nounset

CHAIN_ADDRESS_PREFIX="${CHAIN_ADDRESS_PREFIX:-"agoric"}"
CHAIN_GAS_AMOUNT="${CHAIN_GAS_AMOUNT:-"0.025"}"
CHAIN_GAS_DENOM="${CHAIN_GAS_DENOM:-"ubld"}"
COIN_TYPE="${COIN_TYPE:-"564"}"
CONFIG_FILE_PATH="$RELAYER_HOME/$CHAIN_NAME.json"
GAS_ADJUSTMENT="${GAS_ADJUSTMENT:-"1.2"}"
SKELETON_OBJECT=""

add_chain() {
    relayer chains add "$CHAIN_NAME" --file "$CONFIG_FILE_PATH" --home "$RELAYER_HOME"
}

create_skeleton() {
    SKELETON_OBJECT="$(
        jq '
            {
                "type": "cosmos",
                "value": {
                    "account-prefix": "",
                    "chain-id": "",
                    "coin-type": "",
                    "debug": true,
                    "gas-adjustment": "",
                    "gas-prices": "",
                    "key": "default",
                    "keyring-backend": "test",
                    "output-format": "json",
                    "rpc-addr": "",
                    "sign-mode": "direct",
                    "timeout": "20s"
                }
            }
        ' --null-input
    )"
}

main() {
    create_skeleton
    write_config_file
    add_chain
    rm --force "$CONFIG_FILE_PATH"
}

write_config_file() {
    echo "$SKELETON_OBJECT" |
        jq --arg prefix "$CHAIN_ADDRESS_PREFIX" \
            --arg chain_id "$CHAIN_ID" \
            --arg coin_type "$COIN_TYPE" \
            --arg gas_adjustment "$GAS_ADJUSTMENT" \
            --arg gas_prices "$CHAIN_GAS_AMOUNT$CHAIN_GAS_DENOM" \
            --arg rpc "$CHAIN_RPC" '
      .value["account-prefix"] = $prefix |
      .value["chain-id"] = $chain_id |
      .value["coin-type"] = ($coin_type | tonumber) |
      .value["gas-adjustment"] = ($gas_adjustment | tonumber) |
      .value["gas-prices"] = $gas_prices |
      .value["rpc-addr"] = $rpc
    ' >"$CONFIG_FILE_PATH"
}

main
