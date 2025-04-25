#! /bin/bash
# Built based on:
# https://github.com/cosmos/testnets/blob/master/interchain-security/provider/README.md

set -o errexit -o errtrace -o nounset

CHAIN_GAS_DENOM="uatom"
CHAIN_ID="provider"
CHAIN_NAME="cosmoshubtestnet"
CHAIN_RPC="https://rpc.provider-sentry-01.ics-testnet.polypore.xyz:443"
SKELETON_OBJECT=""

CONFIG_FILE_PATH="$RELAYER_HOME/$CHAIN_NAME.json"

add_chain() {
    relayer chains add "$CHAIN_NAME" \
        --file "$CONFIG_FILE_PATH" --home "$RELAYER_HOME"
}

create_skeleton() {
    SKELETON_OBJECT="$(
        jq '
            {
                "type": "cosmos",
                "value": {
                    "account-prefix": "",
                    "chain-id": "",
                    "coin-type": 118,
                    "debug": true,
                    "gas-adjustment": 1.2,
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
}

write_config_file() {
    echo "$SKELETON_OBJECT" |
        jq --arg prefix "cosmos" \
            --arg chain_id "$CHAIN_ID" \
            --arg gas_prices "0.01$CHAIN_GAS_DENOM" \
            --arg rpc "$CHAIN_RPC" '
      .value["account-prefix"] = $prefix |
      .value["chain-id"] = $chain_id |
      .value["gas-prices"] = $gas_prices |
      .value["rpc-addr"] = $rpc
    ' >"$CONFIG_FILE_PATH"
}

main
