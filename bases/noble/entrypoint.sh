#! /bin/bash

set -o errexit -o xtrace

BINARY_PATH="/state/nobled"
BINARY_VERSION="v10.0.0-beta.1"
NOBLE_HOME="/state/$CHAIN_ID"
SNAPSHOT_HEIGHT="29086165"
TIMESTAMP="$(date '+%s')"

fetch_address_book() {
    curl "https://snapshots.polkachu.com/testnet-addrbook/noble/addrbook.json" \
        --fail --location --output "$NOBLE_HOME/config/addrbook.json" --show-error --silent
}

fetch_snapshot() {
    local snapshot_tar_path="/state/noble.tar.lz4"

    if ! test -f "$snapshot_tar_path"; then
        curl "https://snapshots.polkachu.com/testnet-snapshots/noble/noble_$SNAPSHOT_HEIGHT.tar.lz4" \
            --fail --location --output "$snapshot_tar_path" --show-error --silent
        tar --directory "$NOBLE_HOME" --extract --file "$snapshot_tar_path" --use-compress-program "lz4"
    fi
}

initiate() {
    test -d "$NOBLE_HOME" ||
        mkdir --parents "$NOBLE_HOME"

    test -f "$NOBLE_HOME/config/app.toml" ||
        "$BINARY_PATH" init "$MONIKER" --chain-id "$CHAIN_ID" --home "$NOBLE_HOME" >/dev/null
}

install_binary() {
    local binary_checksum
    local checksum_path="/tmp/nobled-checksum"
    local expected_checksum

    if ! test -f "$BINARY_PATH"; then
        curl "https://github.com/noble-assets/noble/releases/download/$BINARY_VERSION/nobled_linux-amd64" \
            --fail --location --output "$BINARY_PATH" --show-error --silent
        curl "https://github.com/noble-assets/noble/releases/download/$BINARY_VERSION/checksum.txt" \
            --fail --location --output "$checksum_path" --show-error --silent

        chmod +x "$BINARY_PATH"

        binary_checksum="$(sha256sum "$BINARY_PATH" | cut --delimiter ' ' --fields 1)"
        expected_checksum="$(head --lines 1 "$checksum_path" | cut --delimiter ' ' --fields 1)"

        if test "$binary_checksum" != "$expected_checksum"; then
            echo "Checksum mismatch! Expected: '$expected_checksum', Got: '$binary_checksum'"
            exit 1
        else
            rm --force "$checksum_path"
        fi
    fi
}

install_dependencies() {
    apt-get update >/dev/null
    apt-get install curl jq lz4 --yes >/dev/null
}

update_config() {
    sed \
        --expression 's|^laddr = "tcp://127.0.0.1:26657"|laddr = "tcp://0.0.0.0:26657"|g' \
        --in-place \
        "$NOBLE_HOME/config/config.toml"
    sed \
        --expression 's|= "tcp://[^:]*:1317"|= "tcp://0.0.0.0:1317"|g' \
        --expression 's|= "[^:]*:9090"|= "0.0.0.0:9090"|g' \
        --in-place \
        "$NOBLE_HOME/config/app.toml"
}

start_chain() {
    local log_file_path="/state/$TIMESTAMP.log"
    touch "$log_file_path"

    "$BINARY_PATH" start --home "$NOBLE_HOME" --log_format "json" 2>&1 |
        tee "$log_file_path"
}

install_dependencies
install_binary
initiate
fetch_address_book
fetch_snapshot
update_config
start_chain
