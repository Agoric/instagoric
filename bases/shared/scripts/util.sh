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
    local keyNumber="${1:-"0"}"

    echo "$WHALE_SEED" |
        add_key "${WHALE_KEYNAME}_${keyNumber}" \
            --index "$keyNumber" \
            --recover
}

auto_approve() {
    local account_vote=""
    local proposal_id=""
    local proposal_ids=""
    local proposals=""
    local votes=""
    local wallet_name="$1"

    if test "$AUTO_APPROVE_PROPOSAL" == "true"; then
        while true; do
            proposals="$(
                agd query gov proposals \
                    --chain-id "$CHAIN_ID" \
                    --home "$AGORIC_HOME" \
                    --output "json" \
                    --status "VotingPeriod" 2>/dev/null
            )"

            proposal_ids="$(echo "$proposals" | jq --raw-output '.proposals[].id')"

            if test -n "$proposal_ids"; then
                for proposal_id in $proposal_ids; do
                    votes="$(
                        agd query gov votes "$proposal_id" \
                            --chain-id "$CHAIN_ID" \
                            --output json 2>/dev/null
                    )"
                    account_vote="$(
                        test -n "$votes" && echo "$votes" |
                            jq \
                                '.votes[] | select(.voter == $account) | .options[] | .option' \
                                --arg account "$(
                                    agd keys show "$wallet_name" \
                                        --address \
                                        --home "$AGORIC_HOME" \
                                        --keyring-backend "test"
                                )" \
                                --raw-output
                    )"

                    if test "$account_vote" == "$VOTE_OPTION_YES"; then
                        echo "Already voted YES on proposal ID: $proposal_id"
                        continue
                    fi

                    agd tx gov vote "$proposal_id" yes \
                        --chain-id "$CHAIN_ID" \
                        --from "$wallet_name" \
                        --home "$AGORIC_HOME" \
                        --keyring-backend "test" \
                        --yes >/dev/null

                    echo "Voted YES on proposal ID: $proposal_id"
                done
            else
                echo "No new proposals to vote on."
            fi

            sleep $AUTO_APPROVE_POLL_INTERVAL
        done
    fi
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
    local have_value
    local needed
    local new_needed
    local sep
    local to
    local want

    from="$1"
    amount="$2"
    to="$(cat "/state/self.address")"
    want=${amount//,/ }

    while true; do
        have="$(agd query bank balances "$to" --node "$PRIMARY_ENDPOINT:$RPC_PORT" --output "json" | jq --raw-output '.balances')"
        needed=""
        sep=""
        for valueDenom in $want; do
            read -r wantValue denom <<<"$(echo "$valueDenom" | sed --expression 's/\([^0-9].*\)/ \1/')"
            have_value="$(echo "$have" | jq --raw-output ".[] | select(.denom == \"$denom\") | .amount")"
            echo "$denom: have $have_value, want $wantValue"
            new_needed="$wantValue$denom"
            if test -z "$have_value" && ! echo "$needed" | grep --extended-regexp --silent ".*${needed:-$new_needed}.*"; then
                needed="$needed$sep$new_needed"
                sep=","
            fi
        done

        if test -z "$needed"; then
            echo "$to now has at least $amount"
            break
        fi

        if response="$(agd tx bank send "$from" "$to" "$needed" \
            --broadcast-mode "block" \
            --chain-id "$CHAIN_ID" \
            --home "$AGORIC_HOME" \
            --keyring-backend "test" \
            --node "$PRIMARY_ENDPOINT:$RPC_PORT" \
            --output "json" \
            --yes)" && test -n "$response" && test "$(echo "$response" | jq --raw-output '.code')" -eq "0"; then
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
                if ip="$(echo "$json" | jq --raw-output ".ips.\"$service_name\"")"; then
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

patch_validator_config() {
    if test -n "${CONSENSUS_TIMEOUT_PROPOSE}"; then
        sed "$AGORIC_HOME/config/config.toml" \
            --expression "s|^timeout_propose = .*|timeout_propose = '$CONSENSUS_TIMEOUT_PROPOSE'|" \
            --in-place
    fi
    if test -n "${CONSENSUS_TIMEOUT_PREVOTE}"; then
        sed "$AGORIC_HOME/config/config.toml" \
            --expression "s|^timeout_prevote = .*|timeout_prevote = '$CONSENSUS_TIMEOUT_PREVOTE'|" \
            --in-place
    fi
    if test -n "${CONSENSUS_TIMEOUT_PRECOMMIT}"; then
        sed "$AGORIC_HOME/config/config.toml" \
            --expression "s|^timeout_precommit = .*|timeout_precommit = '$CONSENSUS_TIMEOUT_PRECOMMIT'|" \
            --in-place
    fi
    if test -n "${CONSENSUS_TIMEOUT_COMMIT}"; then
        sed "$AGORIC_HOME/config/config.toml" \
            --expression "s|^timeout_commit = .*|timeout_commit = '$CONSENSUS_TIMEOUT_COMMIT'|" \
            --in-place
    fi
}

start_chain() {
    local log_file="$1"
    shift

    (
        cd "$SDK_ROOT_PATH" || exit
        node "/usr/local/bin/ag-chain-cosmos" start \
            --home "$AGORIC_HOME" \
            --log_format "json" \
            "$@" >>"$log_file" 2>&1
    )
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
    local parsed=""
    local response=""
    local stakeamount="400000000ibc/toyusdc"
    local status=""
    local wallet_name="$1"

    while true; do
        if status="$(get_node_info)"; then
            if parsed="$(echo "$status" | jq --raw-output '.SyncInfo.catching_up')"; then
                if test "$parsed" == "false"; then
                    sleep 30
                    response="$(
                        agd tx bank send "$wallet_name" "$PROVISIONING_ADDRESS" "$stakeamount" \
                            --broadcast-mode "block" \
                            --chain-id "$CHAIN_ID" \
                            --home "$AGORIC_HOME" \
                            --keyring-backend "test" \
                            --node "$PRIMARY_ENDPOINT:$RPC_PORT" \
                            --output "json" \
                            --yes
                    )"
                    if test -n "$response" && test "$(echo "$response" | jq --raw-output '.code')" -eq "0"; then
                        touch "$AGORIC_HOME/registered"
                        sleep 10
                        return
                    fi
                else
                    echo "not caught up, waiting to fund provision account"
                fi
            fi
        fi
        sleep 5
    done

}

wait_till_syncup_and_register() {
    local stake_amount="50000000ubld"
    local wallet_name="$1"

    while true; do
        if status="$(get_node_info)"; then
            if parsed="$(echo "$status" | jq --raw-output '.SyncInfo.catching_up')"; then
                if test "$parsed" == "false"; then
                    echo "caught up, register validator"
                    ensure_balance "$wallet_name" "$stake_amount"
                    sleep 10
                    agd tx staking create-validator \
                        --amount "$stake_amount" \
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
