#! /bin/bash

set -o errexit -o errtrace -o nounset

RPC="http://$RPCNODES_SERVICE_HOST:$RPCNODES_SERVICE_PORT"

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
