#!/bin/bash

set +e

CURRENT_DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# shellcheck source=./source.sh
source "$CURRENT_DIRECTORY_PATH/source.sh"

# shellcheck source=./logs-cleanup.sh
/bin/bash "$CURRENT_DIRECTORY_PATH/logs-cleanup.sh" \
    "$APP_LOG_FILE" "$CONTEXTUAL_SLOGFILE" "$OTEL_LOG_FILE" "$SERVER_LOG_FILE" "$SLOGFILE"

# shellcheck source=./util.sh
source "$CURRENT_DIRECTORY_PATH/util.sh"

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

start_helper_wrapper() {
    (start_helper "$SERVER_LOG_FILE" &)
}

start_helper_for_validator() {
    if test -n "$A3P_SNAPSHOT_TIMESTAMP"; then
        WHALE_KEYNAME="$VALIDATOR_KEY_NAME" start_helper_wrapper
    else
        WHALE_KEYNAME="$(get_whale_keyname)" start_helper_wrapper
    fi
}

start_otel_server() {
    if [ -z "$ENABLE_TELEMETRY" ]; then
        echo "skipping telemetry since ENABLE_TELEMETRY is not set"
        unset OTEL_EXPORTER_OTLP_ENDPOINT
        unset OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
    elif [ -f "$USE_OTEL_CONFIG" ]; then
        cd "$HOME" || return

        container_id="$(
            curl "$API_ENDPOINT/api/v1/namespaces/$NAMESPACE/pods?labelSelector=statefulset.kubernetes.io/pod-name%3D$PODNAME" \
                --cacert "$CA_PATH" --header "Authorization: Bearer $(cat "$TOKEN_PATH")" --silent |
                jq --raw-output '.items[] | .status.containerStatuses[] | select(.name == "node") | .containerID' |
                sed --expression 's|containerd://||g'
        )"
        ARCHITECTURE="$(dpkg --print-architecture)"

        echo "starting telemetry collector"
        export CONTAINER_ID="$container_id"

        OTEL_CONFIG="$HOME/instagoric-otel-config.yaml"
        cp "$USE_OTEL_CONFIG" "$OTEL_CONFIG"

        sed "$OTEL_CONFIG" \
            --expression "s/@CHAIN_ID@/$CHAIN_ID/" \
            --expression "s/@CLUSTER_NAME@/$CLUSTER_NAME/" \
            --expression "s/@CONTAINER_ID@/$CONTAINER_ID/" \
            --expression "s/@NAMESPACE@/$NAMESPACE/" \
            --expression "s/@PODNAME@/$PODNAME/" \
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

# agd firstboot
if ! test -f "$AGORIC_HOME/config/config.toml"; then
    firstboot="true"

    if test -n "$A3P_SNAPSHOT_TIMESTAMP"; then
        curl "$A3P_SNAPSHOT_IMAGE_URL/$CHAIN_ID/config-$A3P_SNAPSHOT_TIMESTAMP.tar.gz" \
            --fail --location --output "/state/config.tar.gz" --silent
        curl "$A3P_SNAPSHOT_IMAGE_URL/$CHAIN_ID/data-$A3P_SNAPSHOT_TIMESTAMP.tar.gz" \
            --fail --location --output "/state/data.tar.gz" --silent
        curl "$A3P_SNAPSHOT_IMAGE_URL/$CHAIN_ID/keyring-test-$A3P_SNAPSHOT_TIMESTAMP.tar.gz" \
            --fail --location --output "/state/keyring-test.tar.gz" --silent

        tar --extract --file "/state/config.tar.gz" --gzip --directory "$AGORIC_HOME"
        tar --extract --file "/state/data.tar.gz" --gzip --directory "$AGORIC_HOME"
        tar --extract --file "/state/keyring-test.tar.gz" --gzip --directory "$AGORIC_HOME"

        rm --force "/state/config.tar.gz" "/state/data.tar.gz" "/state/keyring-test.tar.gz"

        if test "$ROLE" == "$VALIDATOR_STATEFUL_SET_NAME" || test "$ROLE" == "$SEED_STATEFUL_SET_NAME"; then
            sed "$AGORIC_HOME/config/config.toml" --expression "s|^moniker = .*|moniker = '$PODNAME'|" --in-place
        else
            if ! test "$ROLE" == "$PRIMARY_VALIDATOR_STATEFUL_SET_NAME"; then
                echo "Not supported for $ROLE pod"
            else
                curl "$A3P_SNAPSHOT_IMAGE_URL/$CHAIN_ID/node-key-$A3P_SNAPSHOT_TIMESTAMP.json" \
                    --fail --location --output "$AGORIC_HOME/config/node_key.json" --silent
                curl "$A3P_SNAPSHOT_IMAGE_URL/$CHAIN_ID/priv-validator-key-$A3P_SNAPSHOT_TIMESTAMP.json" \
                    --fail --location --output "$AGORIC_HOME/config/priv_validator_key.json" --silent
            fi
        fi
    else
        echo "Initializing chain"
        agd init --home "$AGORIC_HOME" --chain-id "$CHAIN_ID" "$PODNAME"
        agoric set-defaults ag-chain-cosmos "$AGORIC_HOME"/config

        # Preserve the node key for this state.
        if [[ ! -f /state/node_key.json ]]; then
            cp "$AGORIC_HOME/config/node_key.json" /state/node_key.json
        fi
        cp /state/node_key.json "$AGORIC_HOME/config/node_key.json"

        if [[ $ROLE == "$PRIMARY_VALIDATOR_STATEFUL_SET_NAME" ]]; then
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
                        agd add-genesis-account "${WHALE_KEYNAME}_${i}" $WHALE_IBC_DENOMS --keyring-backend test --home "$AGORIC_HOME"
                done
            fi
            if [[ -n $FAUCET_ADDRESS ]]; then
                #faucet
                agd add-genesis-account "$FAUCET_ADDRESS" $WHALE_IBC_DENOMS --keyring-backend test --home "$AGORIC_HOME"
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
            if [[ $ROLE != "$FIRST_FORK_STATEFUL_SET_NAME" ]] && [[ $ROLE != "$SECOND_FORK_STATEFUL_SET_NAME" ]] && [[ $ROLE != "$FOLLOWER_STATEFUL_SET_NAME" ]]; then
                get_primary_validator_genesis >"$AGORIC_HOME/config/genesis.json"
            fi
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
    sed -i.bak "/^\[rpc]/,/^\[/{s/^laddr[[:space:]]*=.*/laddr = 'tcp:\/\/0.0.0.0:$RPC_PORT'/}" "$AGORIC_HOME/config/config.toml"
fi

echo "Firstboot: $firstboot"

if test -f "$BOOTSTRAP_CONFIG_PATCH_FILE"; then
    patch --directory "$SDK_ROOT_PATH" --input "$BOOTSTRAP_CONFIG_PATCH_FILE" --strip "1"
fi

case "$ROLE" in
"$PRIMARY_VALIDATOR_STATEFUL_SET_NAME")
    start_helper_for_validator

    if [[ $firstboot == "true" ]]; then
        cp /config/network/node_key.json "$AGORIC_HOME/config/node_key.json"
    fi

    external_address="$(get_ips "$PRIMARY_VALIDATOR_SERVICE_NAME")"
    sed -i.bak "s/^external_address =.*/external_address = \"$external_address:$P2P_PORT\"/" "$AGORIC_HOME/config/config.toml"
    if [[ -n "${ENABLE_XSNAP_DEBUG}" ]]; then
        export XSNAP_TEST_RECORD="${AGORIC_HOME}/xs_test_record_${BOOT_TIME}"
    fi
    patch_validator_config

    export DEBUG="agoric,SwingSet:ls,SwingSet:vat"
    if [[ ! -f "$AGORIC_HOME/registered" ]]; then
        if test -n "$A3P_SNAPSHOT_TIMESTAMP"; then
            wait_till_syncup_and_fund "$VALIDATOR_KEY_NAME" &
        else
            wait_till_syncup_and_fund "$(get_whale_keyname)" &
        fi
    fi

    /bin/bash /entrypoint/cron.sh
    auto_approve "$SELF_KEYNAME" &
    start_chain "$APP_LOG_FILE"
    ;;

"$VALIDATOR_STATEFUL_SET_NAME")
    start_helper_for_validator

    if [[ $firstboot == "true" ]]; then
        create_self_key
        PEERS="$PRIMARY_NOD_PEER_ID@$PRIMARY_VALIDATOR_STATEFUL_SET_NAME.$NAMESPACE.svc.cluster.local:$P2P_PORT"
        SEEDS="$SEED_NOD_PEER_ID@$SEED_STATEFUL_SET_NAME.$NAMESPACE.svc.cluster.local:$P2P_PORT"

        sed -i.bak -e "s/^seeds =.*/seeds = \"$SEEDS\"/; s/^persistent_peers =.*/persistent_peers = \"$PEERS\"/" "$AGORIC_HOME/config/config.toml"
        sed -i.bak "s/^unconditional_peer_ids =.*/unconditional_peer_ids = \"$PRIMARY_NOD_PEER_ID\"/" "$AGORIC_HOME/config/config.toml"
        sed -i.bak "s/^persistent_peers_max_dial_period =.*/persistent_peers_max_dial_period = \"1s\"/" "$AGORIC_HOME/config/config.toml"
    fi
    sed -i.bak "s/^external_address =.*/external_address = \"$POD_IP:$P2P_PORT\"/" "$AGORIC_HOME/config/config.toml"

    if ! test -f "$AGORIC_HOME/registered"; then
        if test -n "$A3P_SNAPSHOT_TIMESTAMP"; then
            wait_till_syncup_and_register "$VALIDATOR_KEY_NAME" &
        else
            add_whale_key "$(get_whale_index)"
            wait_till_syncup_and_register "$(get_whale_keyname)" &
        fi
    fi

    if [[ -n "${ENABLE_XSNAP_DEBUG}" ]]; then
        export XSNAP_TEST_RECORD="${AGORIC_HOME}/xs_test_record_${BOOT_TIME}"
    fi
    export DEBUG="agoric,SwingSet:ls,SwingSet:vat"
    patch_validator_config

    auto_approve "$SELF_KEYNAME" &
    start_chain "$APP_LOG_FILE"
    ;;
"ag-solo")
    sleep infinity
    ;;
"$SEED_STATEFUL_SET_NAME")
    start_helper_for_validator

    primary_validator_external_address="$(get_ips "$PRIMARY_VALIDATOR_SERVICE_NAME")"
    seed_external_address="$(get_ips "$SEED_SERVICE_NAME")"

    PEERS="$PRIMARY_NOD_PEER_ID@$primary_validator_external_address:$P2P_PORT"
    SEEDS="$SEED_NOD_PEER_ID@$seed_external_address:$P2P_PORT"

    if [[ $firstboot == "true" ]]; then
        create_self_key

        cp "/config/network/seed_node_key.json" "$AGORIC_HOME/config/node_key.json"

        sed "$AGORIC_HOME/config/config.toml" \
            --expression "s|^seeds = .*|seeds = '$SEEDS'|" \
            --in-place
        sed "$AGORIC_HOME/config/config.toml" \
            --expression "s|^unconditional_peer_ids = .*|unconditional_peer_ids = '$PRIMARY_NOD_PEER_ID'|" \
            --in-place
        sed "$AGORIC_HOME/config/config.toml" \
            --expression "s|^seed_mode = .*|seed_mode = true|" \
            --in-place
    fi

    sed "$AGORIC_HOME/config/config.toml" \
        --expression "s|^persistent_peers = .*|persistent_peers = '$PEERS'|" \
        --in-place
    sed "$AGORIC_HOME/config/config.toml" \
        --expression "s|^external_address = .*|external_address = '$seed_external_address:$P2P_PORT'|" \
        --in-place

    # Must not run state-sync unless we have enough non-pruned state for it.
    sed -i.bak '/^\[state-sync]/,/^\[/{s/^snapshot-interval[[:space:]]*=.*/snapshot-interval = 0/}' "$AGORIC_HOME/config/app.toml"
    start_chain "$APP_LOG_FILE" --pruning everything
    ;;
"$FIRST_FORK_STATEFUL_SET_NAME")
    WHALE_KEYNAME="$WHALE_KEYNAME" POD_NAME="$FIRST_FORK_STATEFUL_SET_NAME" SEED_ENABLE=no NODE_ID="$FIRST_FORK_NODE_ID" start_helper_wrapper
    fork_setup "agoric1"

    /bin/bash /entrypoint/cron.sh

    export DEBUG="agoric,SwingSet:ls,SwingSet:vat"
    auto_approve "$WHALE_KEYNAME" &
    start_chain "$APP_LOG_FILE" --iavl-disable-fastnode "false"
    ;;
"$SECOND_FORK_STATEFUL_SET_NAME")
    WHALE_KEYNAME="$WHALE_KEYNAME" POD_NAME="$FIRST_FORK_STATEFUL_SET_NAME" SEED_ENABLE=no NODE_ID="$FIRST_FORK_NODE_ID" start_helper_wrapper
    fork_setup "agoric2"
    export DEBUG="agoric,SwingSet:ls,SwingSet:vat"
    auto_approve "$WHALE_KEYNAME" &
    start_chain "$APP_LOG_FILE" --iavl-disable-fastnode "false"
    ;;
"$FOLLOWER_STATEFUL_SET_NAME")
    WHALE_KEYNAME=dummy POD_NAME="$FOLLOWER_STATEFUL_SET_NAME" start_helper_wrapper
    if [[ ! -f "/state/$FOLLOWER_STATEFUL_SET_NAME-initialized" ]]; then
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
        touch /state/$FOLLOWER_STATEFUL_SET_NAME-initialized
    fi

    /bin/bash /entrypoint/cron.sh

    export DEBUG="agoric,SwingSet:ls,SwingSet:vat"
    start_chain "$APP_LOG_FILE"
    ;;
*)
    echo "unknown role"
    exit 1
    ;;
esac

status=$?

hang

echo "exiting entrypoint with status=$status"
exit "$status"
