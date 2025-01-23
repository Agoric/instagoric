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
        have="$(agd query bank balances "$to" --node "$PRIMARY_ENDPOINT:26657" --output "json" | jq --raw-output '.balances')"
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
            --node "${PRIMARY_ENDPOINT}:26657" \
            --yes; then
            echo "successfully sent $amount to $to"
        else
            sleep $(((RANDOM % 50) + 10))
        fi
    done
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

start_chain() {
    local logFile="$1"
    shift

    node /usr/local/bin/ag-chain-cosmos start \
        --home "$AGORIC_HOME" \
        --log_format "json" \
        "$@" >>"$logFile" 2>&1
}

wait_till_syncup_and_register() {
    local stakeamount="50000000ubld"

    while true; do
        if status=$(agd status --home "$AGORIC_HOME"); then
            if parsed=$(echo "$status" | jq --raw-output '.SyncInfo.catching_up'); then
                if [[ $parsed == "false" ]]; then
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
                        --node "$PRIMARY_ENDPOINT:26657" \
                        --pubkey "$(agd tendermint show-validator --home "$AGORIC_HOME")" \
                        --website "http://$POD_IP:26657" \
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
