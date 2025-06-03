#!/bin/bash

set +e

CURRENT_DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# shellcheck source=./source.sh
source "$CURRENT_DIRECTORY_PATH/source.sh"

# shellcheck source=./logs-cleanup.sh
/bin/bash "$CURRENT_DIRECTORY_PATH/logs-cleanup.sh" \
    "$APP_LOG_FILE" "$CONTEXTUAL_SLOGFILE" "$OTEL_LOG_FILE" "$SERVER_LOG_FILE" "$SLOGFILE"

# shellcheck source=./otel.sh
/bin/bash "$CURRENT_DIRECTORY_PATH/otel.sh" >"$OTEL_LOG_FILE" 2>&1 &

# shellcheck source=./util.sh
source "$CURRENT_DIRECTORY_PATH/util.sh"

set -x

mkdir --parents "$AGORIC_HOME" "$TMPDIR"
# shellcheck disable=SC2086,SC2115
rm --force --recursive -- $TMPDIR/..?* $TMPDIR/.[!.]* $TMPDIR/*

resolved_config="${BOOTSTRAP_CONFIG//"@agoric"/"$SDK_ROOT_PATH/packages"}"

ln --force --symbolic "$APP_LOG_FILE" "/state/app.log"
ln --force --symbolic "$OTEL_LOG_FILE" "/state/otel.log"
ln --force --symbolic "$SERVER_LOG_FILE" "/state/server.log"
ln --force --symbolic "$SLOGFILE" "/state/slogfile_current.json"
ln --force --symbolic "$CONTEXTUAL_SLOGFILE" "/state/contextual_slogs.json"

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

echo "ROLE: $ROLE"

echo "whale keyname: $(get_whale_keyname)"
firstboot="false"

update_swingset_config_file "$resolved_config"

# agd firstboot
if ! test -f "$AGORIC_HOME/config/config.toml"; then
    firstboot="true"

    if test -n "$A3P_SNAPSHOT_TIMESTAMP"; then
        setup_a3p_snapshot_data
    else
        initialize_new_chain "$resolved_config"
    fi
fi

echo "Firstboot: $firstboot"

if test -f "$BOOTSTRAP_CONFIG_PATCH_FILE"; then
    patch --directory "$SDK_ROOT_PATH" --input "$BOOTSTRAP_CONFIG_PATCH_FILE" --strip "1"
fi

update_config_files

case "$ROLE" in
"$PRIMARY_VALIDATOR_STATEFUL_SET_NAME")
    start_helper_for_validator

    external_address="$(get_ips "$PRIMARY_VALIDATOR_EXTERNAL_SERVICE_NAME")"
    sed "$AGORIC_HOME/config/config.toml" \
        --expression "s|^external_address =.*|external_address = \"$external_address:$P2P_PORT\"|" \
        --in-place
    if test -n "$ENABLE_XSNAP_DEBUG"; then
        export XSNAP_TEST_RECORD="$AGORIC_HOME/xs_test_record_$BOOT_TIME"
    fi
    patch_validator_config

    export DEBUG="agoric,SwingSet:ls,SwingSet:vat"
    if ! test -f "$AGORIC_HOME/registered"; then
        if test -n "$A3P_SNAPSHOT_TIMESTAMP"; then
            wait_till_syncup_and_fund "$VALIDATOR_KEY_NAME" &
        else
            wait_till_syncup_and_fund "$(get_whale_keyname)" &
        fi
    fi

    /bin/bash "$CURRENT_DIRECTORY_PATH/cron.sh"
    auto_approve "$SELF_KEYNAME" &
    start_chain "$APP_LOG_FILE"
    ;;

"$VALIDATOR_STATEFUL_SET_NAME")
    start_helper_for_validator
    create_self_key

    primary_node_peer_id="$(get_node_id_from_cluster_service "$PRIMARY_VALIDATOR_SERVICE_NAME")"
    PEERS="$primary_node_peer_id@$PRIMARY_VALIDATOR_STATEFUL_SET_NAME.$NAMESPACE.svc.cluster.local:$P2P_PORT"
    SEEDS="$(get_node_id_from_cluster_service "$SEED_SERVICE_NAME")@$SEED_STATEFUL_SET_NAME.$NAMESPACE.svc.cluster.local:$P2P_PORT"

    sed "$AGORIC_HOME/config/config.toml" \
        --expression "s|^external_address =.*|external_address = '$POD_IP:$P2P_PORT'|" \
        --expression "s|^persistent_peers = .*|persistent_peers = '$PEERS'|" \
        --expression "s|^persistent_peers_max_dial_period = .*|persistent_peers_max_dial_period = '1s'|" \
        --expression "s|^seeds =.*|seeds = '$SEEDS'|" \
        --expression "s|^unconditional_peer_ids = .*|unconditional_peer_ids = '$primary_node_peer_id'|" \
        --in-place

    if test -n "$A3P_SNAPSHOT_TIMESTAMP"; then
        wait_till_syncup_and_register "$VALIDATOR_KEY_NAME" &
    else
        add_whale_key "$(get_whale_index)"
        wait_till_syncup_and_register "$(get_whale_keyname)" &
    fi

    if test -n "$ENABLE_XSNAP_DEBUG"; then
        export XSNAP_TEST_RECORD="$AGORIC_HOME/xs_test_record_$BOOT_TIME"
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
    create_self_key

    primary_node_peer_id="$(get_node_id_from_cluster_service "$PRIMARY_VALIDATOR_SERVICE_NAME")"
    primary_validator_external_address="$(get_ips "$PRIMARY_VALIDATOR_EXTERNAL_SERVICE_NAME")"
    seed_external_address="$(get_ips "$SEED_EXTERNAL_SERVICE_NAME")"

    PEERS="$primary_node_peer_id@$primary_validator_external_address:$P2P_PORT"

    sed "$AGORIC_HOME/config/config.toml" \
        --expression "s|^external_address = .*|external_address = '$seed_external_address:$P2P_PORT'|" \
        --expression "s|^persistent_peers = .*|persistent_peers = '$PEERS'|" \
        --expression "s|^seed_mode = .*|seed_mode = true|" \
        --expression "s|^unconditional_peer_ids = .*|unconditional_peer_ids = '$primary_node_peer_id'|" \
        --in-place

    # Must not run state-sync unless we have enough non-pruned state for it.
    sed "$AGORIC_HOME/config/app.toml" \
        --expression '/^\[state-sync]/,/^\[/{s|^snapshot-interval =.*|snapshot-interval = 0|}' \
        --in-place
    start_chain "$APP_LOG_FILE" --pruning everything
    ;;
"$FIRST_FORK_STATEFUL_SET_NAME")
    WHALE_KEYNAME="$WHALE_KEYNAME" POD_NAME="$FIRST_FORK_STATEFUL_SET_NAME" SEED_ENABLE=no NODE_ID="$FIRST_FORK_NODE_ID" start_helper_wrapper
    fork_setup "agoric1"

    /bin/bash "$CURRENT_DIRECTORY_PATH/cron.sh"

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
    WHALE_KEYNAME="dummy" POD_NAME="$FOLLOWER_STATEFUL_SET_NAME" start_helper_wrapper
    if ! test -f "/state/$FOLLOWER_STATEFUL_SET_NAME-initialized"; then
        apt-get update
        apt install lz4 --yes

        if ! test -f "/state/$MAINNET_SNAPSHOT"; then
            curl --location --output "/state/$MAINNET_SNAPSHOT" --silent "$MAINNET_SNAPSHOT_URL/$MAINNET_SNAPSHOT"
        fi

        tar --directory "$AGORIC_HOME" --extract --file "/state/$MAINNET_SNAPSHOT" --use-compress-program "lz4"

        curl "$MAINNET_ADDRBOOK_URL" --fail --location --output "/state/addrbook.json" --silent
        cp --force "/state/addrbook.json" "$AGORIC_HOME/config/addrbook.json"

        sed "$AGORIC_HOME/config/app.toml" \
            --expression 's|^snapshot-interval = .*|snapshot-interval = 0|' \
            --in-place
        touch "/state/$FOLLOWER_STATEFUL_SET_NAME-initialized"
    fi

    /bin/bash "$CURRENT_DIRECTORY_PATH/cron.sh"

    export DEBUG="agoric,SwingSet:ls,SwingSet:vat"
    start_chain "$APP_LOG_FILE"
    ;;
*)
    echo "unknown role"
    exit 1
    ;;
esac

status="$?"

possibly_copy_core_dump_files

hang

echo "exiting entrypoint with status=$status"
exit "$status"
