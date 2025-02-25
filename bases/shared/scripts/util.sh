#! /bin/bash

# shellcheck source=./source.sh
source "$CURRENT_DIRECTORY_PATH/source.sh"

add_key() {
    local keyName="$1"
    shift

    agd keys add "$keyName" \
        --home "$AGORIC_HOME" \
        --keyring-backend "test" \
        "$@"
}

add_whale_key() {
    test -n "$WHALE_SEED" || return 1
    local keyNumber="${1:-0}"

    echo "$WHALE_SEED" |
        add_key "${WHALE_KEYNAME}_${keyNumber}" \
            --index "$keyNumber" \
            --recover
}

create_self_key() {
    add_key "self" >/state/self.out 2>&1
    tail --lines 1 /state/self.out >/state/self.key
    agd keys show "self" \
        --address \
        --home "$AGORIC_HOME" \
        --keyring-backend "test" >/state/self.address
}

ensure_balance() {
    local amount
    local from
    local have
    local haveValue
    local needed
    local sep
    local to
    local want

    from="$1"
    amount="$2"
    to="$(cat /state/self.address)"
    want=${amount//,/ }

    while true; do
        have="$(agd query bank balances "$to" --node "$PRIMARY_ENDPOINT:$RPC_PORT" --output "json" | jq --raw-output '.balances')"
        for valueDenom in $want; do
            # shellcheck disable=SC2001
            read -r wantValue denom <<<"$(echo "$valueDenom" | sed -e 's/\([^0-9].*\)/ \1/')"
            haveValue="$(echo "$have" | jq --raw-output ".[] | select(.denom == \"$denom\") | .amount")"
            echo "$denom: have $haveValue, want $wantValue"
            if test -z "$haveValue"; then
                needed="$needed$sep$wantValue$denom"
                sep=,
            fi
        done

        if test -z "$needed"; then
            echo "$to now has at least $amount"
            break
        fi

        if agd tx bank send "$from" "$to" "$needed" \
            --broadcast-mode "block" \
            --chain-id "$CHAIN_ID" \
            --home "$AGORIC_HOME" \
            --keyring-backend "test" \
            --node "$PRIMARY_ENDPOINT:$RPC_PORT" \
            --yes; then
            echo "successfully sent $amount to $to"
        else
            sleep $(((RANDOM % 50) + 10))
        fi
    done
}

get_ips() {
    local service_name=$1

    while true; do
        if json=$(curl --fail --max-time "15" --silent --show-error "http://localhost:$PRIVATE_APP_PORT/ips"); then
            if test "$(echo "$json" | jq --raw-output '.status')" == "1"; then
                if ip="$(echo "$json" | jq --raw-output ".ips.$service_name")"; then
                    echo "$ip"
                    break
                fi
            fi
        fi

        sleep 2
    done
}

get_node_info() {
    agd status --home "$AGORIC_HOME"
}

get_pod_ip() {
    local app_label_value="$1"
    local pod_info
    local pod_ip

    while true; do
        pod_info=$(
            curl "$API_ENDPOINT/api/v1/namespaces/$NAMESPACE/pods" \
                --cacert "$CA_PATH" \
                --header "Authorization: Bearer $TOKEN" \
                --insecure \
                --show-error \
                --silent
        )
        pod_ip=$(
            echo "$pod_info" |
                jq '.items[] | select(.metadata.labels.app == $app_label) | .status.podIP' \
                    --arg "app_label" "$app_label_value" \
                    --raw-output
        )

        if test -z "$pod_ip"; then
            echo "Couldn't get Pod IP address. Trying again..." >&2
        else
            break
        fi

        sleep 10
    done

    echo "$pod_ip"
}

get_primary_validator_genesis() {
    while true; do
        if json=$(curl --fail --max-time "15" --silent --show-error "$PRIMARY_ENDPOINT:$PRIVATE_APP_PORT/genesis.json"); then
            echo "$json"
            break
        fi
        sleep 2
    done
}

get_whale_index() {
    podnum=$(echo "$PODNAME" | grep --only-matching '[0-9]*$')

    case $PODNAME in
    validator-primary-*)
        echo 0
        return
        ;;
    validator-*)
        echo "$((1 + podnum))"
        return
        ;;
    esac
}

get_whale_keyname() {
    echo "${WHALE_KEYNAME}_$(get_whale_index)"
}

hang() {
    local pid
    local slept

    if test -n "$HANG_FILE_PATH" && test -f "$HANG_FILE_PATH"; then
        echo 1>&2 "$HANG_FILE_PATH exists, keeping entrypoint alive..."
    fi

    while test -z "$HANG_FILE_PATH" || test -f "$HANG_FILE_PATH"; do
        sleep 600 &
        pid="$!"

        echo 1>&2 "still hanging: to exit kill $pid"
        wait "$pid"
        slept="$?"
        test "$slept" -eq "0" || break
    done
}

start_chain() {
    local log_file="$1"
    shift

    node "/usr/local/bin/ag-chain-cosmos" start \
        --home "$AGORIC_HOME" \
        --log_format "json" \
        "$@" >>"$log_file" 2>&1
}

start_helper() {
    local log_file="$1"
    local server_directory="/usr/src/instagoric-server"

    rm --force --recursive "$server_directory"
    mkdir --parents "$server_directory" || exit
    cp /config/server/* "$server_directory" || exit
    (
        cd "$server_directory" || exit
        yarn --production
        while true; do
            yarn start >"$log_file" 2>&1
            sleep 1
        done
    )
}

wait_for_pod() {
    local app_label_value="$1"
    local pod_info
    local pod_phase

    while true; do
        pod_info=$(
            curl "$API_ENDPOINT/api/v1/namespaces/$NAMESPACE/pods" \
                --cacert "$CA_PATH" \
                --header "Authorization: Bearer $TOKEN" \
                --insecure \
                --show-error \
                --silent
        )
        pod_phase=$(
            echo "$pod_info" |
                jq '.items[] | select(.metadata.labels.app == $app_label) | .status.phase' \
                    --arg "app_label" "$app_label_value" \
                    --raw-output
        )

        if test "$pod_phase" != "Running"; then
            echo "Pod not running yet. Trying again..."
        else
            break
        fi

        sleep 10
    done
}

wait_till_syncup_and_fund() {
    local stakeamount="400000000ibc/toyusdc"

    while true; do
        if status="$(get_node_info)"; then
            if parsed="$(echo "$status" | jq --raw-output '.SyncInfo.catching_up')"; then
                if test "$parsed" == "false"; then
                    sleep 30
                    agd tx bank send "$(get_whale_keyname)" "$PROVISIONING_ADDRESS" "$stakeamount" \
                        --broadcast-mode "block" \
                        --chain-id="$CHAIN_ID" \
                        --home "$AGORIC_HOME" \
                        --keyring-backend "test" \
                        --node "$PRIMARY_ENDPOINT:$RPC_PORT" \
                        --yes
                    touch "$AGORIC_HOME/registered"

                    sleep 10
                    return
                else
                    echo "not caught up, waiting to fund provision account"
                fi
            fi
        fi
        sleep 5
    done

}

wait_till_syncup_and_register() {
    local stakeamount="50000000ubld"

    while true; do
        if status="$(get_node_info)"; then
            if parsed="$(echo "$status" | jq --raw-output '.SyncInfo.catching_up')"; then
                if test "$parsed" == "false"; then
                    echo "caught up, register validator"
                    ensure_balance "$(get_whale_keyname)" "$stakeamount"
                    sleep 10
                    agd tx staking create-validator \
                        --amount "$stakeamount" \
                        --chain-id "$CHAIN_ID" \
                        --commission-max-change-rate "0.01" \
                        --commission-max-rate "0.20" \
                        --commission-rate "0.10" \
                        --details "" \
                        --from "self" \
                        --gas "auto" \
                        --gas-adjustment "1.4" \
                        --home "$AGORIC_HOME" \
                        --keyring-backend "test" \
                        --min-self-delegation "1" \
                        --moniker "$PODNAME" \
                        --node "$PRIMARY_ENDPOINT:$RPC_PORT" \
                        --pubkey "$(agd tendermint show-validator --home "$AGORIC_HOME")" \
                        --website "http://$POD_IP:$RPC_PORT" \
                        --yes
                    touch "$AGORIC_HOME/registered"

                    sleep 10
                    return
                else
                    echo "not caught up, waiting to register validator"
                fi
            fi
        fi
        sleep 5
    done
}
