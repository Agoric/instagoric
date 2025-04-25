#! /bin/bash

set -o errexit -o errtrace

CHAIN_NAME="osmosistestnet"
RPC="https://rpc.osmotest5.osmosis.zone:443" # Other endpoint has transaction indexing disabled

ensure_correct_rpc() {
    if test "$(
        relayer chains show "$CHAIN_NAME" --home "$RELAYER_HOME" --json |
            jq --raw-output '.value."rpc-addr"'
    )" != "$RPC"; then
        relayer chains set-rpc-addr "$CHAIN_NAME" "$RPC" --home "$RELAYER_HOME"
    fi
}

ensure_correct_rpc
