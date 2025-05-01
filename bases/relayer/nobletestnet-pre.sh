#! /bin/bash

set -o nounset

MINIUM_REQUIRED_HEIGHT="10"
RPC="http://$NOBLE_SERVICE_SERVICE_HOST:$NOBLE_SERVICE_SERVICE_PORT_RPC"

wait_for_progress() {
    local node_status

    echo "Waiting for some progress on chain"

    while true; do
        node_status="$(curl "$RPC/status" --max-time "5" --silent 2>/dev/null)"

        if test "$(
            echo "$node_status" | jq --raw-output '.result.sync_info.catching_up'
        )" == "false" && test "$(
            echo "$node_status" | jq --raw-output '.result.sync_info.latest_block_height'
        )" -gt "$MINIUM_REQUIRED_HEIGHT"; then
            break
        else
            sleep 2
        fi
    done

    echo "Node has caught up and has height above $MINIUM_REQUIRED_HEIGHT"
}

wait_for_rpc() {
    local status_code

    echo "Waiting for rpc '$RPC' to respond"

    while true; do
        curl "$RPC" --max-time "5" --silent >/dev/null 2>&1
        status_code="$?"

        echo "rpc '$RPC' responded with '$status_code'"

        if ! test "$status_code" -eq "0"; then
            sleep 5
        else
            break
        fi
    done

    echo "rpc '$RPC' is up"
}

wait_for_rpc
wait_for_progress
