#! /bin/bash
# shellcheck disable=SC2207

set -o errexit -o errtrace -o xtrace

if test -z "$RELAYER_CONNECTIONS"; then
    echo "No relayer connections configured"
    sleep infinity
fi

ALL_CHAINS=("")
CONFIG_FILE_PATH="$RELAYER_HOME/config/config.yaml"
CONNECTIONS=("")
DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
KEY_NAME=${KEY_NAME:-"My Wallet"}
RELAYER_BINARY_EXPECTED_MD5_HASH="34496ca949e0e8fd7d9ab0514554b0a6"
RELAYER_MNEMONIC=${RELAYER_MNEMONIC:-"orbit bench unit task food shock brand bracket domain regular warfare company announce wheel grape trust sphere boy doctor half guard ritual three ecology"}
RELAYER_PATH="/bin/relayer"

add_chains() {
    for chain in "${ALL_CHAINS[@]}"; do
        if ! relayer chains show "$chain" --home "$RELAYER_HOME" >/dev/null 2>&1; then
            if test -f "$DIRECTORY_PATH/$chain.sh"; then
                /bin/bash "$DIRECTORY_PATH/$chain.sh"
            else
                TESTNET_FLAG=""
                if [[ "$chain" =~ ^.*testnet$ ]]; then
                    TESTNET_FLAG="--testnet"
                fi
                relayer chains add "$chain" --home "$RELAYER_HOME" "$TESTNET_FLAG"
            fi

            if test -f "$DIRECTORY_PATH/$chain-post.sh"; then
                /bin/bash "$DIRECTORY_PATH/$chain-post.sh"
            fi

        fi
    done
}

add_keys() {
    for chain in "${ALL_CHAINS[@]}"; do
        if ! relayer keys show "$chain" "$KEY_NAME" --home "$RELAYER_HOME" >/dev/null 2>&1; then
            relayer keys restore "$chain" "$KEY_NAME" "$RELAYER_MNEMONIC" \
                --home "$RELAYER_HOME"
        fi
        if ! test "$(
            relayer config show --home "$RELAYER_HOME" --json |
                jq --arg chain "$chain" --raw-output '.chains[$chain].value.key'
        )" == "$KEY_NAME"; then
            relayer keys use "$chain" "$KEY_NAME" --home "$RELAYER_HOME"
        fi
    done
}

add_paths() {
    local mapping=""
    local first_chain_id=""
    local second_chain_id=""

    for path_name in "${CONNECTIONS[@]}"; do
        if ! relayer paths show "$path_name" --home "$RELAYER_HOME" >/dev/null 2>&1; then
            mapping="$(
                echo "$path_name" |
                    jq --compact-output --raw-input '{ first: (split("<->")[0]), second: (split("<->")[1]) }'
            )"

            first_chain_id=$(
                relayer chains show "$(echo "$mapping" | jq --raw-output '.first')" --home "$RELAYER_HOME" --json |
                    jq --raw-output '.value."chain-id"'
            )
            second_chain_id=$(
                relayer chains show "$(echo "$mapping" | jq --raw-output '.second')" --home "$RELAYER_HOME" --json |
                    jq --raw-output '.value."chain-id"'
            )

            relayer paths new "$first_chain_id" "$second_chain_id" "$path_name" --home "$RELAYER_HOME"
        fi

        if ! test "$(relayer paths show "$path_name" --home "$RELAYER_HOME" --json | jq --raw-output '.status.connection')" == "true"; then
            relayer transact link "$path_name" \
                --home "$RELAYER_HOME" --log-format "json" --override
        fi
    done

}

fetch_binary() {
    curl "https://storage.googleapis.com/simulationlab_cloudbuild/rly" --output "$RELAYER_PATH"
    chmod +x "$RELAYER_PATH"

    RELAYER_BINARY_RECEIVED_MD5_HASH="$(md5sum "$RELAYER_PATH" --binary | awk '{ print $1 }')"

    if test "$RELAYER_BINARY_EXPECTED_MD5_HASH" != "$RELAYER_BINARY_RECEIVED_MD5_HASH"; then
        echo "Expected hash: $RELAYER_BINARY_EXPECTED_MD5_HASH, Received hash: $RELAYER_BINARY_RECEIVED_MD5_HASH"
        exit 1
    fi
}

get_connections() {
    CONNECTIONS=($(
        echo "$RELAYER_CONNECTIONS" |
            jq --raw-input --raw-output 'split(",") | .[]'
    ))
}

get_unique_chains() {
    ALL_CHAINS=($(
        echo "$RELAYER_CONNECTIONS" |
            jq --raw-input --raw-output '
            split(",")
            | map(split("<->"))
            | add
            | unique
            | .[]
        '
    ))
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
    get_unique_chains
    get_connections
    initiate_configuration
    add_chains
    add_keys
    add_paths
    start_relayer
}

start_relayer() {
    local args

    args=($(echo "$RELAYER_CONNECTIONS" | jq --raw-input --raw-output 'split(",") | join(" ")'))

    relayer start "${args[@]}" \
        --home "$RELAYER_HOME" --log-format "json" --log-level "debug"
}

main
