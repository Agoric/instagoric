#!/bin/bash

set +e

CURRENT_DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# shellcheck source=./source.sh
source "$CURRENT_DIRECTORY_PATH/source.sh"

# shellcheck source=./logs-cleanup.sh
/bin/bash "$CURRENT_DIRECTORY_PATH/logs-cleanup.sh" \
    "$APP_LOG_FILE" "$CONTEXTUAL_SLOGFILE" "$OTEL_LOG_FILE" "$SERVER_LOG_FILE" "$SLOGFILE"

set -x

mkdir --parents "$AGORIC_HOME" "$TMPDIR"
# shellcheck disable=SC2086,SC2115
rm --force --recursive -- $TMPDIR/..?* $TMPDIR/.[!.]* $TMPDIR/*
mkdir --parents /state/cores
chmod a+rwx /state/cores

echo "/state/cores/core.%e.%p.%h.%t" >/proc/sys/kernel/core_pattern

# Copy a /config/network/$basename to $BOOTSTRAP_CONFIG
resolved_config=$(echo "$BOOTSTRAP_CONFIG" | sed 's_@agoric_/usr/src/agoric-sdk/packages_g')
resolved_basename=$(basename "$resolved_config")
source_config="/config/network/$resolved_basename"
test ! -e "$source_config" || cp "$source_config" "$resolved_config"

ln --force --symbolic "$APP_LOG_FILE" /state/app.log
ln --force --symbolic "$OTEL_LOG_FILE" /state/otel.log
ln --force --symbolic "$SERVER_LOG_FILE" /state/server.log
ln --force --symbolic "$SLOGFILE" /state/slogfile_current.json
ln --force --symbolic "$CONTEXTUAL_SLOGFILE" /state/contextual_slogs.json

primary_genesis() {
    while true; do
        if json=$(curl --fail -m 15 -sS "$PRIMARY_ENDPOINT:8002/genesis.json"); then
            echo "$json"
            break
        fi
        sleep 2
    done
}

add_whale_key() {
    keynum=${1:-0}
    [[ -n "$WHALE_SEED" ]] || return 1
    echo "$WHALE_SEED" | agd keys add "${WHALE_KEYNAME}_${keynum}" --index "$keynum" --recover --home "$AGORIC_HOME" --keyring-backend test
}

create_self_key() {
    agd keys add self --home "$AGORIC_HOME" --keyring-backend test >/state/self.out 2>&1
    tail -n1 /state/self.out >/state/self.key
    key_address=$(agd keys show self -a --home "$AGORIC_HOME" --keyring-backend test)
    echo "$key_address" >/state/self.address
}

get_whale_index() {
    podnum=$(echo "$PODNAME" | grep -o '[0-9]*$')

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
    idx=$(get_whale_index)
    echo "${WHALE_KEYNAME}_${idx}"
}

wait_till_syncup_and_register() {
    while true; do
        if status=$(agd status --home="$AGORIC_HOME"); then
            if parsed=$(echo "$status" | jq -r .SyncInfo.catching_up); then
                if [[ $parsed == "false" ]]; then
                    echo "caught up, register validator"
                    stakeamount="50000000ubld"
                    ensure_balance "$(get_whale_keyname)" "$stakeamount"
                    sleep 10
                    agd tx staking create-validator \
                        --home="$AGORIC_HOME" \
                        --amount="${stakeamount}" \
                        --pubkey="$(agd tendermint show-validator --home=$AGORIC_HOME)" \
                        --moniker="$PODNAME" \
                        --website="http://$POD_IP:26657" \
                        --details="" \
                        --node="$PRIMARY_ENDPOINT:26657" \
                        --commission-rate="0.10" \
                        --commission-max-rate="0.20" \
                        --commission-max-change-rate="0.01" \
                        --min-self-delegation="1" \
                        --from=self \
                        --keyring-backend=test \
                        --chain-id="$CHAIN_ID" \
                        --gas=auto \
                        --gas-adjustment=1.4 \
                        -y
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

wait_till_syncup_and_fund() {
    while true; do
        if status=$(agd status --home="$AGORIC_HOME"); then
            if parsed=$(echo "$status" | jq -r .SyncInfo.catching_up); then
                if [[ $parsed == "false" ]]; then
                    sleep 30
                    stakeamount="400000000ibc/toyusdc"

                    agd tx bank send -b block "$(get_whale_keyname)" "agoric1megzytg65cyrgzs6fvzxgrcqvwwl7ugpt62346" "$stakeamount" \
                        --node "${PRIMARY_ENDPOINT}:26657" -y --keyring-backend=test --home="$AGORIC_HOME" --chain-id="$CHAIN_ID"
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

ensure_balance() {
    from=$1
    amount=$2
    to=${3:-$(cat /state/self.address)}

    want=${amount//,/ }
    while true; do
        have=$(agd query bank balances "$to" --node "$PRIMARY_ENDPOINT:26657" -ojson | jq -r '.balances')
        needed=
        sep=
        for valueDenom in $want; do
            read -r wantValue denom <<<"$(echo "$valueDenom" | sed -e 's/\([^0-9].*\)/ \1/')"
            haveValue=$(echo "$have" | jq -r ".[] | select(.denom == \"$denom\") | .amount")
            echo "$denom: have $haveValue, want $wantValue"
            if [[ -z "$haveValue" ]]; then
                needed="$needed$sep$wantValue$denom"
                sep=,
            #elif (( wantValue > haveValue )); then
            #  needed="$needed$sep$(( wantValue - haveValue ))$denom"
            #  sep=,
            fi
        done
        if [ -z "$needed" ]; then
            echo "$to now has at least $amount"
            break
        fi
        if agd tx bank send -b block "$from" "$to" "$needed" \
            --node "${PRIMARY_ENDPOINT}:26657" -y --keyring-backend=test \
            --home="$AGORIC_HOME" --chain-id="$CHAIN_ID"; then
            echo "successfully sent $amount to $to"
        else
            sleep $(((RANDOM % 50) + 10))
        fi
    done
}

start_helper() {
    (
        SRV=/usr/src/instagoric-server
        rm -rf "$SRV"
        mkdir -p "$SRV" || exit
        cp /config/server/* "$SRV" || exit
        cd "$SRV" || exit
        yarn --production
        while true; do
            yarn start >>"$SERVER_LOG_FILE" 2>&1
            sleep 1
        done
    )
}

auto_approve() {
    if [ "$AUTO_APPROVE_PROPOSAL" = "true" ]; then
        POLL_INTERVAL=10
        FROM_ACCOUNT=self

        while true; do
            # Query for proposals with status "PROPOSAL_STATUS_VOTING_PERIOD"
            PROPOSALS=$(agd query gov proposals --status VotingPeriod --chain-id=$CHAIN_ID --home=$AGORIC_HOME --output json 2>/dev/null)

            # Extract proposal IDs
            PROPOSAL_IDS=$(echo $PROPOSALS | jq -r '.proposals[].id')

            echo $PROPOSAL_IDS

            if [ -n "$PROPOSAL_IDS" ]; then
                for PROPOSAL_ID in $PROPOSAL_IDS; do
                    # Skip processing if already voted YES on the proposal with self account

                    VOTES=$(agd query gov votes $PROPOSAL_ID --chain-id=$CHAIN_ID --output json 2>/dev/null)
                    ACCOUNT_VOTE=$([ -n "$VOTES" ] && echo $VOTES | jq -r --arg account $(agd keys show $FROM_ACCOUNT -a --home=$AGORIC_HOME --keyring-backend=test) '.votes[] | select(.voter == $account) | .options[] | .option')

                    if [ "$ACCOUNT_VOTE" == "VOTE_OPTION_YES" ]; then
                        echo "Already voted YES on proposal ID: $PROPOSAL_ID"
                        continue
                    fi

                    # Vote YES on the proposal
                    agd tx gov vote $PROPOSAL_ID yes \
                        --from=$FROM_ACCOUNT --chain-id=$CHAIN_ID --keyring-backend=test --home=$AGORIC_HOME --yes >/dev/null

                    echo "Voted YES on proposal ID: $PROPOSAL_ID"
                done
            else
                echo "No new proposals to vote on."
            fi

            # Wait for the next poll
            sleep $POLL_INTERVAL
        done
    fi
}

start_chain() {
    # shellcheck disable=SC2068
    auto_approve &

    (
        cd /usr/src/agoric-sdk &&
            node /usr/local/bin/ag-chain-cosmos --home "$AGORIC_HOME" start --log_format=json $@ >>"$APP_LOG_FILE" 2>&1
    )
}

hang() {
    hangfile="$1"
    if [ -n "$hangfile" ] && [ -f "$hangfile" ]; then
        echo 1>&2 "$hangfile exists, keeping entrypoint alive..."
    fi
    while [ -z "$hangfile" ] || [ -f "$hangfile" ]; do
        sleep 600 &
        pid=$!

        echo 1>&2 "still hanging: to exit kill $pid"
        wait $pid
        slept=$?
        [ $slept -eq 0 ] || break
    done
}

get_ips() {
    servicename=$1
    while true; do
        if json=$(curl --fail -m 15 -sS "localhost:8002/ips"); then
            if [[ "$(echo "$json" | jq -r .status)" == "1" ]]; then
                if ip=$(echo "$json" | jq -r ".ips.\"$servicename\""); then
                    echo "$ip"
                    break
                fi
            fi
        fi

        sleep 2
    done
}

get_pod_ip() {
    # Define your variable
    app_label_value=$1

    while true; do
        pod_info=$(curl -sSk -H "Authorization: Bearer $TOKEN" --cacert $CA_PATH $API_ENDPOINT/api/v1/namespaces/$NAMESPACE/pods/)
        pod_ip=$(echo "$pod_info" | jq --arg app_value "$app_label_value" -r '.items[] | select(.metadata.labels.app == $app_value) .status.podIP')

        if [[ -z "$pod_ip" ]]; then
            echo "Couldn't get Pod IP address. Trying again..."
        else
            break
        fi
        sleep 10
    done

    echo "$pod_ip"
}

wait_for_pod() {
    # Define your variable
    app_label_value=$1

    while true; do
        pod_info=$(curl -sSk -H "Authorization: Bearer $TOKEN" --cacert $CA_PATH $API_ENDPOINT/api/v1/namespaces/$NAMESPACE/pods/)
        pod_phase=$(echo "$pod_info" | jq --arg app_value "$app_label_value" -r '.items[] | select(.metadata.labels.app == $app_value) .status.phase')

        if [[ "$pod_phase" != "Running" ]]; then
            echo "Pod not running yet. Trying again..."
        else
            break
        fi
        sleep 10
    done
}

fork_setup() {
    THIS_FORK=$1
    wait_for_pod "fork1"
    wait_for_pod "fork2"

    echo "Fetching IP addresses of the two nodes..."
    FORK1_IP=$(get_pod_ip "fork1")
    FORK2_IP=$(get_pod_ip "fork2")

    if [ ! -f "/state/$THIS_FORK-config-$MAINFORK_HEIGHT.tar.gz" ]; then
        mkdir -p $AGORIC_HOME
        rm -rf $AGORIC_HOME/*

        apt install -y axel
        axel --quiet -n 10 -o "/state/$THIS_FORK-config-$MAINFORK_HEIGHT.tar.gz" "$MAINFORK_IMAGE_URL/$THIS_FORK-config-$MAINFORK_HEIGHT.tar.gz"
        axel --quiet -n 10 -o "/state/agoric-$MAINFORK_HEIGHT.tar.gz" "$MAINFORK_IMAGE_URL/agoric-$MAINFORK_HEIGHT.tar.gz"

        tar -xzf "/state/$THIS_FORK-config-$MAINFORK_HEIGHT.tar.gz" -C $AGORIC_HOME
        tar -xzf "/state/agoric-$MAINFORK_HEIGHT.tar.gz" -C $AGORIC_HOME
    fi

    persistent_peers="persistent_peers = \"0663e8221928c923d516ea1e8972927f54da9edb@$FORK1_IP:26656,e234dc7fffdea593c5338a9dd8b5c22ba00731eb@$FORK2_IP:26656\""
    sed -i "/^persistent_peers =/s/.*/$persistent_peers/" $AGORIC_HOME/config/config.toml
}

start_otel_server() {
    if [ -z "$ENABLE_TELEMETRY" ]; then
        echo "skipping telemetry since ENABLE_TELEMETRY is not set"
        unset OTEL_EXPORTER_OTLP_ENDPOINT
        unset OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
    elif [ -f "$USE_OTEL_CONFIG" ]; then
        cd "$HOME" || return

        container_id=$(
            grep systemd </proc/self/cgroup |
                head --lines 1 |
                cut --delimiter / --fields 4
        )
        ARCHITECTURE="$(dpkg --print-architecture)"

        echo "starting telemetry collector"
        export CONTAINER_ID="$container_id"

        OTEL_CONFIG="$HOME/instagoric-otel-config.yaml"
        cp "$USE_OTEL_CONFIG" "$OTEL_CONFIG"

        sed "$OTEL_CONFIG" \
            --expression "s/@CHAIN_ID@/${CHAIN_ID}/" \
            --expression "s/@CONTAINER_ID@/${CONTAINER_ID}/" \
            --expression "s/@HONEYCOMB_API_KEY@/${HONEYCOMB_API_KEY}/" \
            --expression "s/@HONEYCOMB_DATASET@/${HONEYCOMB_DATASET}/" \
            --expression "s/@NAMESPACE@/${NAMESPACE}/" \
            --in-place

        curl "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}/otelcol-contrib_${OTEL_VERSION}_linux_${ARCHITECTURE}.tar.gz" \
            --location --output otel.tgz
        tar --extract --file otel.tgz --gzip
        "$HOME/otelcol-contrib" --config "$OTEL_CONFIG" >>"$OTEL_LOG_FILE" 2>&1
    fi
}

###
start_otel_server &

echo "ROLE: $ROLE"
echo "whale keyname: $(get_whale_keyname)"
firstboot="false"

whaleibcdenoms="10000000000000000ubld,10000000000000000uist,1000000provisionpass,1000000000000000000ibc/toyatom,1000000000000000000ibc/toyusdc,1000000000000000000ibc/toyollie,8000000000000ibc/toyellie,1000000000000000000ibc/usdc1234,1000000000000000000ibc/usdt1234,1000000000000000000ibc/06362C6F7F4FB702B94C13CD2E7C03DEC357683FD978936340B43FBFBC5351EB"

if [[ -n "${GC_INTERVAL}" ]]; then
    jq '. + {defaultReapInterval: $freq}' --arg freq $GC_INTERVAL /usr/src/agoric-sdk/packages/vats/decentral-core-config.json >$BOOTSTRAP_CONFIG
    export BOOTSTRAP_CONFIG="@agoric/vats/decentral-core-config-modified.json"
fi

if [[ -n "${ECON_SOLO_SEED}" ]]; then
    econ_addr=$(echo "$ECON_SOLO_SEED" | agd keys add econ --dry-run --recover --output json | jq -r .address)
    #        jq '. + {defaultReapInterval: $freq}' --arg freq $GC_INTERVAL /usr/src/agoric-sdk/packages/vats/decentral-core-config.json > /usr/src/agoric-sdk/node_modules/\@agoric/vats/decentral-core-config-modified.json
    sed "s/@FIRST_SOLO_ADDRESS@/$econ_addr/g" /config/network/economy-proposals.json >/tmp/formatted_proposals.json
    source_bootstrap="/usr/src/agoric-sdk/packages/vats/decentral-core-config.json"
    if [[ -f /usr/src/agoric-sdk/packages/vats/decentral-core-config-modified.json ]]; then
        source_bootstrap="/usr/src/agoric-sdk/packages/vats/decentral-core-config-modified.json"
    fi

    contents="$(jq -s '.[0] + {coreProposals:.[1]}' $source_bootstrap /tmp/formatted_proposals.json)" && echo -E "${contents}" >/usr/src/agoric-sdk/packages/vats/decentral-core-config-modified.json
    export BOOTSTRAP_CONFIG="@agoric/vats/decentral-core-config-modified.json"
fi

if [[ -n "${PSM_GOV_A}" ]]; then
    resolved_config=$(echo "$BOOTSTRAP_CONFIG" | sed 's_@agoric_/usr/src/agoric-sdk/packages_g')
    cp "$resolved_config" "$MODIFIED_BOOTSTRAP_PATH"
    export BOOTSTRAP_CONFIG="$MODIFIED_BOOTSTRAP_PATH"
    addr1=$(echo "$PSM_GOV_A" | agd keys add econ --dry-run --recover --output json | jq -r .address)
    addr2=$(echo "$PSM_GOV_B" | agd keys add econ --dry-run --recover --output json | jq -r .address)
    addr3=$(echo "$PSM_GOV_C" | agd keys add econ --dry-run --recover --output json | jq -r .address)

    contents=$(jq ".vats.bootstrap.parameters.economicCommitteeAddresses? |= {\"gov1\":\"$addr1\",\"gov2\":\"$addr2\",\"gov3\":\"$addr3\"}" $BOOTSTRAP_CONFIG) && echo -E "${contents}" >"$BOOTSTRAP_CONFIG"
fi

if [[ -n "${ENDORSED_UI}" ]]; then
    resolved_config=$(echo "$BOOTSTRAP_CONFIG" | sed 's_@agoric_/usr/src/agoric-sdk/packages_g')
    cp "$resolved_config" "$MODIFIED_BOOTSTRAP_PATH"
    export BOOTSTRAP_CONFIG="$MODIFIED_BOOTSTRAP_PATH"
    sed -i "s/bafybeidvpbtlgefi3ptuqzr2fwfyfjqfj6onmye63ij7qkrb4yjxekdh3e/$ENDORSED_UI/" $MODIFIED_BOOTSTRAP_PATH
fi

#agd firstboot
if [[ ! -f "$AGORIC_HOME/config/config.toml" ]]; then
    # ari's terrible docker fix, please eventually remove
    apt-get install -y nano tmux netcat

    firstboot="true"
    echo "Initializing chain"
    agd init --home "$AGORIC_HOME" --chain-id "$CHAIN_ID" "$PODNAME"
    agoric set-defaults ag-chain-cosmos "$AGORIC_HOME"/config

    # Preserve the node key for this state.
    if [[ ! -f /state/node_key.json ]]; then
        cp "$AGORIC_HOME/config/node_key.json" /state/node_key.json
    fi
    cp /state/node_key.json "$AGORIC_HOME/config/node_key.json"

    if [[ $ROLE == "validator-primary" ]]; then
        if [[ -n "${GC_INTERVAL}" ]] && [[ -n "$HONEYCOMB_API_KEY" ]]; then
            timestamp=$(date +%s)
            curl "https://api.honeycomb.io/1/markers/$HONEYCOMB_DATASET" -X POST \
                -H "X-Honeycomb-Team: $HONEYCOMB_API_KEY" \
                -d "{\"message\":\"GC_INTERVAL: ${GC_INTERVAL}\", \"type\":\"deploy\", \"start_time\":${timestamp}}"
        fi
        create_self_key
        agd add-genesis-account self 50000000ubld --keyring-backend test --home "$AGORIC_HOME"

        if [[ -n $WHALE_SEED ]]; then
            for ((i = 0; i <= WHALE_DERIVATIONS; i++)); do
                add_whale_key $i &&
                    agd add-genesis-account "${WHALE_KEYNAME}_${i}" $whaleibcdenoms --keyring-backend test --home "$AGORIC_HOME"
            done
        fi
        if [[ -n $FAUCET_ADDRESS ]]; then
            #faucet
            agd add-genesis-account "$FAUCET_ADDRESS" $whaleibcdenoms --keyring-backend test --home "$AGORIC_HOME"
        fi

        agd gentx self 50000000ubld \
            --chain-id=$CHAIN_ID \
            --moniker="agoric0" \
            --ip="127.0.0.1" \
            --website=https://agoric.com \
            --details=agoric0 \
            --commission-rate="0.10" \
            --commission-max-rate="0.20" \
            --commission-max-change-rate="0.01" \
            --min-self-delegation="1" \
            --keyring-backend=test \
            --home "$AGORIC_HOME"

        agd collect-gentxs --home "$AGORIC_HOME"

        contents="$(jq ".app_state.swingset.params.bootstrap_vat_config = \"$BOOTSTRAP_CONFIG\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" >$AGORIC_HOME/config/genesis.json
        contents="$(jq ".app_state.crisis.constant_fee.denom = \"ubld\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" >$AGORIC_HOME/config/genesis.json
        contents="$(jq ".app_state.mint.params.mint_denom = \"ubld\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" >$AGORIC_HOME/config/genesis.json
        contents="$(jq ".app_state.gov.deposit_params.min_deposit[0].denom = \"ubld\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" >$AGORIC_HOME/config/genesis.json
        contents="$(jq ".app_state.staking.params.bond_denom = \"ubld\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" >$AGORIC_HOME/config/genesis.json
        contents="$(jq ".app_state.slashing.params.signed_blocks_window = \"10000\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" >$AGORIC_HOME/config/genesis.json
        contents="$(jq ".app_state.mint.minter.inflation = \"0.000000000000000000\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" >$AGORIC_HOME/config/genesis.json
        contents="$(jq ".app_state.mint.params.inflation_rate_change = \"0.000000000000000000\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" >$AGORIC_HOME/config/genesis.json
        contents="$(jq ".app_state.mint.params.inflation_min = \"0.000000000000000000\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" >$AGORIC_HOME/config/genesis.json
        contents="$(jq ".app_state.mint.params.inflation_max = \"0.000000000000000000\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" >$AGORIC_HOME/config/genesis.json
        contents="$(jq ".app_state.gov.voting_params.voting_period = \"$VOTING_PERIOD\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" >$AGORIC_HOME/config/genesis.json

        if [[ -n "${BLOCK_COMPUTE_LIMIT}" ]]; then
            # TODO: Select blockComputeLimit by name instead of index
            contents="$(jq ".app_state.swingset.params.beans_per_unit[0].beans = \"$BLOCK_COMPUTE_LIMIT\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" >$AGORIC_HOME/config/genesis.json
        fi
        cp $AGORIC_HOME/config/genesis.json $AGORIC_HOME/config/genesis_final.json

    else
        if [[ $ROLE != fork* ]] && [[ $ROLE != "follower" ]]; then
            primary_genesis >$AGORIC_HOME/config/genesis.json
        fi
    fi
    sed -i.bak 's/^log_level/# log_level/' "$AGORIC_HOME/config/config.toml"

    if [[ -n "${PRUNING}" ]]; then
        sed -i.bak "s/^pruning =.*/pruning = \"$PRUNING\"/" "$AGORIC_HOME/config/app.toml"
    else
        sed -i.bak 's/^pruning-keep-recent =.*/pruning-keep-recent = 10000/' "$AGORIC_HOME/config/app.toml"
        sed -i.bak 's/^pruning-keep-every =.*/pruning-keep-every = 1000/' "$AGORIC_HOME/config/app.toml"
        sed -i.bak 's/^pruning-interval =.*/pruning-interval = 1000/' "$AGORIC_HOME/config/app.toml"
        sed -i.bak '/^\[state-sync]/,/^\[/{s/^snapshot-interval[[:space:]]*=.*/snapshot-interval = 1000/}' "$AGORIC_HOME/config/app.toml"
        sed -i.bak '/^\[state-sync]/,/^\[/{s/^snapshot-keep-recent[[:space:]]*=.*/snapshot-keep-recent = 10/}' "$AGORIC_HOME/config/app.toml"
    fi

    sed -i.bak 's/^allow_duplicate_ip =.*/allow_duplicate_ip = true/' "$AGORIC_HOME/config/config.toml"
    sed -i.bak 's/^prometheus = false/prometheus = true/' "$AGORIC_HOME/config/config.toml"
    sed -i.bak 's/^addr_book_strict = true/addr_book_strict = false/' "$AGORIC_HOME/config/config.toml"
    sed -i.bak 's/^max_num_inbound_peers =.*/max_num_inbound_peers = 150/' "$AGORIC_HOME/config/config.toml"
    sed -i.bak 's/^max_num_outbound_peers =.*/max_num_outbound_peers = 150/' "$AGORIC_HOME/config/config.toml"
    sed -i.bak '/^\[telemetry]/,/^\[/{s/^laddr[[:space:]]*=.*/laddr = "tcp:\/\/0.0.0.0:26652"/}' "$AGORIC_HOME/config/app.toml"
    sed -i.bak '/^\[telemetry]/,/^\[/{s/^prometheus-retention-time[[:space:]]*=.*/prometheus-retention-time = 60/}' "$AGORIC_HOME/config/app.toml"
    sed -i.bak '/^\[telemetry]/,/^\[/{s/^enabled[[:space:]]*=.*/enabled = true/}' "$AGORIC_HOME/config/app.toml"
    sed -i.bak '/^\[api]/,/^\[/{s/^enable[[:space:]]*=.*/enable = true/}' "$AGORIC_HOME/config/app.toml"
    sed -i.bak '/^\[api]/,/^\[/{s/^enabled-unsafe-cors[[:space:]]*=.*/enabled-unsafe-cors = true/}' "$AGORIC_HOME/config/app.toml"
    sed -i.bak '/^\[api]/,/^\[/{s/^swagger[[:space:]]*=.*/swagger = false/}' "$AGORIC_HOME/config/app.toml"
    sed -i.bak '/^\[api]/,/^\[/{s/^address[[:space:]]*=.*/address = "tcp:\/\/0.0.0.0:1317"/}' "$AGORIC_HOME/config/app.toml"
    sed -i.bak '/^\[api]/,/^\[/{s/^max-open-connections[[:space:]]*=.*/max-open-connections = 1000/}' "$AGORIC_HOME/config/app.toml"
    sed -i.bak 's/^rpc-max-body-bytes =.*/rpc-max-body-bytes = \"15000000\"/' "$AGORIC_HOME/config/app.toml"
    sed -i.bak '/^\[rpc]/,/^\[/{s/^laddr[[:space:]]*=.*/laddr = "tcp:\/\/0.0.0.0:26657"/}' "$AGORIC_HOME/config/config.toml"
fi

patch_validator_config() {
    if [[ -n "${CONSENSUS_TIMEOUT_PROPOSE}" ]]; then
        sed -i.bak "s/^timeout_propose =.*/timeout_propose = \"$CONSENSUS_TIMEOUT_PROPOSE\"/" "$AGORIC_HOME/config/config.toml"
    fi
    if [[ -n "${CONSENSUS_TIMEOUT_PREVOTE}" ]]; then
        sed -i.bak "s/^timeout_prevote =.*/timeout_prevote = \"$CONSENSUS_TIMEOUT_PREVOTE\"/" "$AGORIC_HOME/config/config.toml"
    fi
    if [[ -n "${CONSENSUS_TIMEOUT_PRECOMMIT}" ]]; then
        sed -i.bak "s/^timeout_precommit =.*/timeout_precommit = \"$CONSENSUS_TIMEOUT_PRECOMMIT\"/" "$AGORIC_HOME/config/config.toml"
    fi
    if [[ -n "${CONSENSUS_TIMEOUT_COMMIT}" ]]; then
        sed -i.bak "s/^timeout_commit =.*/timeout_commit = \"$CONSENSUS_TIMEOUT_COMMIT\"/" "$AGORIC_HOME/config/config.toml"
    fi
}

echo "Firstboot: $firstboot"

case "$ROLE" in
"validator-primary")
    (WHALE_KEYNAME=$(get_whale_keyname) start_helper &)
    if [[ $firstboot == "true" ]]; then
        cp /config/network/node_key.json "$AGORIC_HOME/config/node_key.json"
    fi

    external_address=$(get_ips validator-primary-ext)
    sed -i.bak "s/^external_address =.*/external_address = \"$external_address:26656\"/" "$AGORIC_HOME/config/config.toml"
    if [[ -n "${ENABLE_XSNAP_DEBUG}" ]]; then
        export XSNAP_TEST_RECORD="${AGORIC_HOME}/xs_test_record_${BOOT_TIME}"
    fi
    patch_validator_config

    export DEBUG="agoric,SwingSet:ls,SwingSet:vat"
    if [[ ! -f "$AGORIC_HOME/registered" ]]; then
        (wait_till_syncup_and_fund) &
    fi

    /bin/bash /entrypoint/cron.sh
    start_chain
    ;;

"validator")
    (WHALE_KEYNAME=$(get_whale_keyname) start_helper &)
    # wait for network live
    if [[ $firstboot == "true" ]]; then
        add_whale_key "$(get_whale_index)"
        create_self_key
        PEERS="$PRIMARY_NOD_PEER_ID@validator-primary.$NAMESPACE.svc.cluster.local:26656"
        SEEDS="$SEED_NOD_PEER_ID@seed.$NAMESPACE.svc.cluster.local:26656"

        sed -i.bak -e "s/^seeds =.*/seeds = \"$SEEDS\"/; s/^persistent_peers =.*/persistent_peers = \"$PEERS\"/" "$AGORIC_HOME/config/config.toml"
        sed -i.bak "s/^unconditional_peer_ids =.*/unconditional_peer_ids = \"$PRIMARY_NOD_PEER_ID\"/" "$AGORIC_HOME/config/config.toml"
        sed -i.bak "s/^persistent_peers_max_dial_period =.*/persistent_peers_max_dial_period = \"1s\"/" "$AGORIC_HOME/config/config.toml"
    fi
    sed -i.bak "s/^external_address =.*/external_address = \"$POD_IP:26656\"/" "$AGORIC_HOME/config/config.toml"
    if [[ ! -f "$AGORIC_HOME/registered" ]]; then
        (wait_till_syncup_and_register) &
    fi

    if [[ -n "${ENABLE_XSNAP_DEBUG}" ]]; then
        export XSNAP_TEST_RECORD="${AGORIC_HOME}/xs_test_record_${BOOT_TIME}"
    fi
    export DEBUG="agoric,SwingSet:ls,SwingSet:vat"
    patch_validator_config

    start_chain
    ;;
"ag-solo")
    sleep infinity
    ;;
"seed")
    (WHALE_KEYNAME=$(get_whale_keyname) start_helper &)
    if [[ $firstboot == "true" ]]; then
        create_self_key
        # wait for network live

        cp /config/network/seed_node_key.json "$AGORIC_HOME/config/node_key.json"
        PEERS="$PRIMARY_NOD_PEER_ID@validator-primary.$NAMESPACE.svc.cluster.local:26656"

        sed -i.bak -e "s/^seeds =.*/seeds = \"$SEEDS\"/; s/^persistent_peers =.*/persistent_peers = \"$PEERS\"/" "$AGORIC_HOME/config/config.toml"
        sed -i.bak "s/^unconditional_peer_ids =.*/unconditional_peer_ids = \"$PRIMARY_NOD_PEER_ID\"/" "$AGORIC_HOME/config/config.toml"
        sed -i.bak "s/^seed_mode =.*/seed_mode = true/" "$AGORIC_HOME/config/config.toml"
    fi
    external_address=$(get_ips seed-ext)
    sed -i.bak "s/^external_address =.*/external_address = \"$external_address:26656\"/" "$AGORIC_HOME/config/config.toml"

    # Must not run state-sync unless we have enough non-pruned state for it.
    sed -i.bak '/^\[state-sync]/,/^\[/{s/^snapshot-interval[[:space:]]*=.*/snapshot-interval = 0/}' "$AGORIC_HOME/config/app.toml"
    start_chain --pruning everything
    ;;
"fork1")
    (WHALE_KEYNAME=whale POD_NAME=fork1 SEED_ENABLE=no NODE_ID='0663e8221928c923d516ea1e8972927f54da9edb' start_helper &)
    fork_setup agoric1

    /bin/bash /entrypoint/cron.sh

    export DEBUG="agoric,SwingSet:ls,SwingSet:vat"
    start_chain --iavl-disable-fastnode false
    ;;
"fork2")
    (WHALE_KEYNAME=whale POD_NAME=fork1 SEED_ENABLE=no NODE_ID='0663e8221928c923d516ea1e8972927f54da9edb' start_helper &)
    fork_setup agoric2
    export DEBUG="agoric,SwingSet:ls,SwingSet:vat"
    start_chain --iavl-disable-fastnode false
    ;;
"follower")
    (WHALE_KEYNAME=dummy POD_NAME=follower start_helper &)
    if [[ ! -f "/state/follower-initialized" ]]; then
        cd /state/
        if [[ ! -f "/state/$MAINNET_SNAPSHOT" ]]; then
            apt install -y axel
            axel --quiet -n 10 -o "$MAINNET_SNAPSHOT" "$MAINNET_SNAPSHOT_URL/$MAINNET_SNAPSHOT" || exit 1
        fi
        apt update
        apt install lz4
        lz4 -c -d "$MAINNET_SNAPSHOT" | tar -x -C $AGORIC_HOME
        wget -O addrbook.json "$MAINNET_ADDRBOOK_URL"
        cp -f addrbook.json "$AGORIC_HOME/config/addrbook.json"
        # disable rosetta
        cat $AGORIC_HOME/config/app.toml | tr '\n' '\r' | sed -e 's/\[rosetta\]\renable = true/\[rosetta\]\renable = false/' | tr '\r' '\n' | tee $AGORIC_HOME/config/app-new.toml
        mv -f $AGORIC_HOME/config/app-new.toml $AGORIC_HOME/config/app.toml
        sed -i 's/^snapshot-interval = .*/snapshot-interval = 0/' $AGORIC_HOME/config/app.toml
        touch /state/follower-initialized
    fi

    /bin/bash /entrypoint/cron.sh

    export DEBUG="agoric,SwingSet:ls,SwingSet:vat"
    start_chain
    ;;
*)
    echo "unknown role"
    exit 1
    ;;
esac

status=$?

hang /state/hang

echo "exiting entrypoint with status=$status"
exit "$status"
