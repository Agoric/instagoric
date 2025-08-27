#! /bin/bash
# shellcheck disable=SC2119,SC2120,SC2155,SC2235

CURRENT_DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>"$VOID" && pwd)"

# shellcheck source=./source.sh
source "$CURRENT_DIRECTORY_PATH/source.sh"

add_key() {
    local keyName="$1"
    shift

    agd keys add "$keyName" \
        --keyring-backend "test" \
        "$@"
}

add_whale_key() {
    test -n "$WHALE_SEED" || return 1
    local key_number="${1:-"0"}"
    local wallet_name="${WHALE_KEYNAME}_${key_number}"

    agd keys show "$wallet_name" --home "$AGORIC_HOME" --keyring-backend "test" >"$VOID" 2>&1 ||
        echo "$WHALE_SEED" |
        add_key "$wallet_name" \
            --home "$AGORIC_HOME" \
            --index "$key_number" \
            --recover
}

auto_approve() {
    local account_vote=""
    local proposal_id=""
    local proposal_ids=""
    local proposals=""
    local proposals_filter=("--proposal-status" "passed")
    local votes=""
    local wallet_name="$1"

    if semver_comparison "$(get_agd_sdk_version)" "$LESS_THAN_COMPARATOR" "$(echo "$SDK_VERSIONS" | jq '."0.50.14"' --raw-output)"; then
        proposals_filter=("--status" "VotingPeriod")
    fi

    if test "$AUTO_APPROVE_PROPOSAL" == "true"; then
        while true; do
            proposals="$(
                agd query gov proposals \
                    --home "$AGORIC_HOME" \
                    --output "json" \
                    "${proposals_filter[@]}" 2>"$VOID"
            )"

            proposal_ids="$(echo "$proposals" | jq --raw-output 'if .proposals == null then "" else .proposals[].id end')"

            if test -n "$proposal_ids"; then
                for proposal_id in $proposal_ids; do
                    votes="$(
                        agd query gov votes "$proposal_id" \
                            --home "$AGORIC_HOME" \
                            --output "json" 2>"$VOID"
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
                        --yes >"$VOID"

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
    agd keys show "$SELF_KEYNAME" --home "$AGORIC_HOME" --keyring-backend "test" >"$VOID" 2>&1 ||
        add_key "$SELF_KEYNAME" --home "$AGORIC_HOME" >"/state/$SELF_KEYNAME.out"
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
    to="$(agd keys show "$SELF_KEYNAME" --address --home "$AGORIC_HOME" --keyring-backend "test")"
    want=${amount//,/ }

    while true; do
        have="$(
            agd query bank balances "$to" \
                --home "$AGORIC_HOME" \
                --node "$PRIMARY_VALIDATOR_SERVICE_URL:$RPC_PORT" \
                --output "json" |
                jq --raw-output '.balances'
        )"
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
            --node "$PRIMARY_VALIDATOR_SERVICE_URL:$RPC_PORT" \
            --output "json" \
            --yes)" && test -n "$response" && test "$(echo "$response" | jq --raw-output '.code')" -eq "0"; then
            echo "successfully sent $amount to $to"
        else
            sleep $(((RANDOM % 50) + 10))
        fi
    done
}

export_neo4j_env() {
    if test -d "$NEO4J_CONFIG_MOUNT_PATH"; then
        export NEO4J_PASSWORD="$(cat "$NEO4J_CONFIG_MOUNT_PATH/PASSWORD")"
        export NEO4J_URI="neo4j://$NEO4J_GATEWAY_SERVICE_HOST:$NEO4J_GATEWAY_SERVICE_PORT_BOLT"
        export NEO4J_USER="$(cat "$NEO4J_CONFIG_MOUNT_PATH/USERNAME")"
    fi
}

fork_setup() {
    local first_fork_ip=""
    local fork_name="$1"
    local second_fork_ip=""

    wait_for_pod "$FIRST_FORK_STATEFUL_SET_NAME"
    wait_for_pod "$SECOND_FORK_STATEFUL_SET_NAME"

    echo "Fetching IP addresses of the two nodes..."
    first_fork_ip="$(get_pod_ip "$FIRST_FORK_STATEFUL_SET_NAME")"
    second_fork_ip="$(get_pod_ip "$SECOND_FORK_STATEFUL_SET_NAME")"

    if ! test -f "/state/config-$MAINFORK_TIMESTAMP.tar.gz"; then
        mkdir --parents "$AGORIC_HOME"
        # shellcheck disable=SC2115,SC2086
        rm --force --recursive $AGORIC_HOME/*

        curl --output "/state/config-$MAINFORK_TIMESTAMP.tar.gz" --silent \
            "$MAINFORK_IMAGE_URL/${fork_name}_config_$MAINFORK_TIMESTAMP.tar.gz"
        curl --output "/state/data-$MAINFORK_TIMESTAMP.tar.gz" --silent \
            "$MAINFORK_IMAGE_URL/agoric_$MAINFORK_TIMESTAMP.tar.gz"
        curl --output "/state/keyring-test.tar.gz" --silent "$MAINFORK_IMAGE_URL/keyring-test.tar.gz"

        tar --extract --file "/state/config-$MAINFORK_TIMESTAMP.tar.gz" --gzip --directory "$AGORIC_HOME"
        tar --extract --file "/state/data-$MAINFORK_TIMESTAMP.tar.gz" --gzip --directory "$AGORIC_HOME"
        tar --extract --file "/state/keyring-test.tar.gz" --gzip --directory "$AGORIC_HOME"

        curl --output "$AGORIC_HOME/data/priv_validator_state.json" --silent \
            "$MAINFORK_IMAGE_URL/priv_validator_state.json"

        rm --force "/state/data-$MAINFORK_TIMESTAMP.tar.gz" "/state/keyring-test.tar.gz"
    fi

    sed "$AGORIC_HOME/config/config.toml" \
        --expression "s|^persistent_peers = .*|persistent_peers = '$FIRST_FORK_NODE_ID@$first_fork_ip:$P2P_PORT,$SECOND_FORK_NODE_ID@$second_fork_ip:$P2P_PORT'|" \
        --in-place

}

get_agd_sdk_version() {
    agd version --long --output "json" | jq '.cosmos_sdk_version' --raw-output
}

get_ips() {
    local service_name=$1

    while true; do
        if json=$(curl --fail --max-time "15" --show-error --silent "http://localhost:$PRIVATE_APP_PORT/ips"); then
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

get_node_id_from_cluster_service() {
    local service_name="$1"
    local node_info=""

    while true; do
        node_info="$(get_node_info "http://$service_name.$NAMESPACE.svc.cluster.local:$RPC_PORT")"
        if test -n "$node_info"; then
            echo "$node_info" | jq '.node_info.id' --raw-output
            break
        fi
        sleep 5
    done
}

get_node_info() {
    local node_url="${1:-"http://0.0.0.0:$RPC_PORT"}"
    curl --fail --location --max-time "5" --silent "$node_url/status" | jq '.result' --raw-output
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
        if json=$(curl --fail --max-time "15" --silent --show-error "$PRIMARY_VALIDATOR_SERVICE_URL:$PRIVATE_APP_PORT/genesis.json"); then
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

has_node_caught_up() {
    test "$(get_node_info | jq --raw-output '.sync_info.catching_up')" == "false"
}

initialize_new_chain() {
    local current_config
    local resolved_config="$1"

    current_config="$(cat "$resolved_config")"

    echo "Initializing chain"
    agd init --chain-id "$CHAIN_ID" --home "$AGORIC_HOME" "$PODNAME"
    agoric set-defaults ag-chain-cosmos "$AGORIC_HOME/config"

    if ! test -f "/state/$NODE_KEY_FILE_NAME"; then
        cp "$AGORIC_HOME/config/$NODE_KEY_FILE_NAME" "/state/$NODE_KEY_FILE_NAME"
    fi

    cp "/state/$NODE_KEY_FILE_NAME" "$AGORIC_HOME/config/$NODE_KEY_FILE_NAME"

    if test "$ROLE" == "$PRIMARY_VALIDATOR_STATEFUL_SET_NAME"; then
        create_self_key
        agd add-genesis-account "$SELF_KEYNAME" "50000000ubld" --home "$AGORIC_HOME" --keyring-backend "test"

        if test -n "$WHALE_SEED"; then
            for ((i = 0; i <= WHALE_DERIVATIONS; i++)); do
                add_whale_key "$i"
                agd add-genesis-account "${WHALE_KEYNAME}_${i}" "$WHALE_IBC_DENOMS" --home "$AGORIC_HOME" --keyring-backend "test"
            done
        fi

        if test -n "$FAUCET_ADDRESS"; then
            agd add-genesis-account "$FAUCET_ADDRESS" "$WHALE_IBC_DENOMS" --home "$AGORIC_HOME" --keyring-backend "test"
        fi

        agd gentx "$SELF_KEYNAME" "50000000ubld" \
            --chain-id "$CHAIN_ID" \
            --commission-max-change-rate "0.01" \
            --commission-max-rate "0.20" \
            --commission-rate "0.10" \
            --details "$PRIMARY_VALIDATOR_MONIKER_NAME" \
            --home "$AGORIC_HOME" \
            --ip "127.0.0.1" \
            --keyring-backend "test" \
            --min-self-delegation "1" \
            --moniker "$PRIMARY_VALIDATOR_MONIKER_NAME"

        agd collect-gentxs --home "$AGORIC_HOME"

        contents="$(
            jq --arg config_file_path "${resolved_config//"$SDK_ROOT_PATH/packages"/"@agoric"}" \
                --arg denom "$BLD_DENOM" \
                --arg voting_period "$VOTING_PERIOD" \
                '
                .app_state.swingset.params.bootstrap_vat_config = $config_file_path |
                .app_state.crisis.constant_fee.denom = $denom |
                .app_state.mint.params.mint_denom = $denom |
                .app_state.gov.deposit_params.min_deposit[0].denom = $denom |
                .app_state.staking.params.bond_denom = $denom |
                .app_state.slashing.params.signed_blocks_window = "10000" |
                .app_state.mint.minter.inflation = "0.000000000000000000" |
                .app_state.mint.params.inflation_rate_change = "0.000000000000000000" |
                .app_state.mint.params.inflation_min = "0.000000000000000000" |
                .app_state.mint.params.inflation_max = "0.000000000000000000" |
                .app_state.gov.voting_params.voting_period = $voting_period
            ' <"$GENESIS_FILE_PATH"
        )"

        if test -n "$BLOCK_COMPUTE_LIMIT"; then
            # TODO: Select blockComputeLimit by name instead of index
            contents="$(
                echo "$contents" |
                    jq --arg block_compute_limit "$BLOCK_COMPUTE_LIMIT" \
                        '.app_state.swingset.params.beans_per_unit[0].beans = $block_compute_limit'
            )"
        fi

        echo -E "$contents" >"$GENESIS_FILE_PATH"

    else
        if test "$ROLE" != "$FIRST_FORK_STATEFUL_SET_NAME" && test "$ROLE" != "$SECOND_FORK_STATEFUL_SET_NAME" && test "$ROLE" != "$FOLLOWER_STATEFUL_SET_NAME"; then
            get_primary_validator_genesis >"$GENESIS_FILE_PATH"
        fi
    fi
}

patch_validator_config() {
    if test -n "$CONSENSUS_TIMEOUT_PROPOSE"; then
        sed "$AGORIC_HOME/config/config.toml" \
            --expression "s|^timeout_propose = .*|timeout_propose = '$CONSENSUS_TIMEOUT_PROPOSE'|" \
            --in-place
    fi
    if test -n "$CONSENSUS_TIMEOUT_PREVOTE"; then
        sed "$AGORIC_HOME/config/config.toml" \
            --expression "s|^timeout_prevote = .*|timeout_prevote = '$CONSENSUS_TIMEOUT_PREVOTE'|" \
            --in-place
    fi
    if test -n "$CONSENSUS_TIMEOUT_PRECOMMIT"; then
        sed "$AGORIC_HOME/config/config.toml" \
            --expression "s|^timeout_precommit = .*|timeout_precommit = '$CONSENSUS_TIMEOUT_PRECOMMIT'|" \
            --in-place
    fi
    if test -n "$CONSENSUS_TIMEOUT_COMMIT"; then
        sed "$AGORIC_HOME/config/config.toml" \
            --expression "s|^timeout_commit = .*|timeout_commit = '$CONSENSUS_TIMEOUT_COMMIT'|" \
            --in-place
    fi
}

possibly_copy_core_dump_files() {
    mkdir --parents "$CORE_DUMP_FILES_DIRECTORY"

    ###########################################################################
    # The default system core dump files have the format `/core.%e.%p.%t`     #
    # When the entrypoint script exits, we will try to copy any dump files    #
    # for future debugging purpose. Note that this will not always work       #
    # as there is no guarantee that the dump file is created by that time,    #
    # or wether a dump file was created at all                                #
    ###########################################################################
    sleep 5
    find "/" -maxdepth "1" -name "core.*" -print0 |
        xargs --null --replace="_file_" cp _file_ "$CORE_DUMP_FILES_DIRECTORY"
}

semver_comparison() {
    local v1="$(echo "$1" | cut --delimiter "-" --fields "1" | tr --delete "v")"
    local op="$2"
    local v2="$(echo "$3" | cut --delimiter "-" --fields "1" | tr --delete "v")"

    IFS='.' read -a v1_parts -r <<< "$v1"
    IFS='.' read -a v2_parts -r <<< "$v2"

    local len1="${#v1_parts[@]}"
    local len2="${#v2_parts[@]}"
    local max_len="$(( "$len1" > "$len2" ? "$len1" : "$len2" ))"

    for ((i=0; i<"$max_len"; i++)); do
        local p1="${v1_parts[i]:-0}"
        local p2="${v2_parts[i]:-0}"

        if (("$p1" < "$p2")); then
            [[ "$op" == "$LESS_THAN_COMPARATOR" || "$op" == "$LESS_THAN_EQUAL_TO_COMPARATOR" || "$op" == "$NOT_EQUAL_TO_COMPARATOR" ]] && return 0
            return 1
        elif (("$p1" > "$p2")); then
            [[ "$op" == "$GREATER_THAN_COMPARATOR" || "$op" == "$GREATER_THAN_EQUAL_TO_COMPARATOR" || "$op" == "$NOT_EQUAL_TO_COMPARATOR" ]] && return 0
            return 1
        fi
    done

    [[ "$op" == "$EQUAL_TO_COMPARATOR" || "$op" == "$LESS_THAN_EQUAL_TO_COMPARATOR" || "$op" == "$GREATER_THAN_EQUAL_TO_COMPARATOR" ]] && return 0
    return 1
}

setup_a3p_snapshot_data() {
    local config_zip_path="/state/config.tar.gz"
    local data_zip_path="/state/data.tar.gz"
    local key_ring_zip_path="/state/keyring-test.tar.gz"

    curl "$A3P_SNAPSHOT_IMAGE_URL/$CHAIN_ID/config-$A3P_SNAPSHOT_TIMESTAMP.tar.gz" \
        --fail --location --output "$config_zip_path" --silent
    curl "$A3P_SNAPSHOT_IMAGE_URL/$CHAIN_ID/data-$A3P_SNAPSHOT_TIMESTAMP.tar.gz" \
        --fail --location --output "$data_zip_path" --silent
    curl "$A3P_SNAPSHOT_IMAGE_URL/$CHAIN_ID/keyring-test-$A3P_SNAPSHOT_TIMESTAMP.tar.gz" \
        --fail --location --output "$key_ring_zip_path" --silent

    tar --extract --file "$config_zip_path" --gzip --directory "$AGORIC_HOME"
    tar --extract --file "$data_zip_path" --gzip --directory "$AGORIC_HOME"
    tar --extract --file "$key_ring_zip_path" --gzip --directory "$AGORIC_HOME"

    rm --force "$config_zip_path" "$data_zip_path" "$key_ring_zip_path"

    if test "$ROLE" == "$VALIDATOR_STATEFUL_SET_NAME" || test "$ROLE" == "$SEED_STATEFUL_SET_NAME"; then
        sed "$AGORIC_HOME/config/config.toml" --expression "s|^moniker = .*|moniker = '$PODNAME'|" --in-place
    else
        if test "$ROLE" != "$PRIMARY_VALIDATOR_STATEFUL_SET_NAME"; then
            echo "Not supported for $ROLE pod"
        else
            curl "$A3P_SNAPSHOT_IMAGE_URL/$CHAIN_ID/node-key-$A3P_SNAPSHOT_TIMESTAMP.json" \
                --fail --location --output "$AGORIC_HOME/config/$NODE_KEY_FILE_NAME" --silent
            curl "$A3P_SNAPSHOT_IMAGE_URL/$CHAIN_ID/priv-validator-key-$A3P_SNAPSHOT_TIMESTAMP.json" \
                --fail --location --output "$AGORIC_HOME/config/priv_validator_key.json" --silent
        fi
    fi
}

setup_neo4j() {
    local config_path="/state/neo4j"
    local slogger_path="slogger.js"

    local file_paths=(
        ".yarn/patches/agoric-telemetry.patch"
        "$slogger_path"
        ".yarnrc.yml"
        "package.json"
        "yarn.lock"
    )
    local slogger_file_path="$config_path/$slogger_path"

    if (
        test "$ROLE" == "$FOLLOWER_STATEFUL_SET_NAME" ||
            test "$ROLE" == "$FIRST_FORK_STATEFUL_SET_NAME" ||
            test "$ROLE" == "$PRIMARY_VALIDATOR_STATEFUL_SET_NAME"
    ) && test -d "$NEO4J_CONFIG_MOUNT_PATH"; then
        for path in "${file_paths[@]}"; do
            mkdir --parents "$config_path/$(dirname "$path")"
            curl --fail --location --output "$config_path/$path" --silent "$NEO4J_SOURCE_URL/$path"
        done

        cp --recursive "$NEO4J_CONFIG_MOUNT_PATH" "$config_path"

        cd "$config_path" || return 1
        corepack enable
        yarn install

        wait_for_url "http://$NEO4J_GATEWAY_SERVICE_HOST:$NEO4J_GATEWAY_SERVICE_PORT_HTTP"

        if test -z "$SLOGSENDER"; then
            export SLOGSENDER="$slogger_file_path"
        else
            export SLOGSENDER="$SLOGSENDER,$slogger_file_path"
        fi
    fi

    export_neo4j_env
}

start_chain() {
    local log_file="$1"
    shift

    setup_neo4j

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

    export_neo4j_env

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

update_config_files() {
    if test -n "$PRUNING"; then
        sed --in-place "s/^pruning =.*/pruning = \"$PRUNING\"/" "$AGORIC_HOME/config/app.toml"
    else
        sed "$AGORIC_HOME/config/app.toml" \
            --expression 's|^pruning-interval =.*|pruning-interval = 1000|' \
            --expression 's|^pruning-keep-every =.*|pruning-keep-every = 1000|' \
            --expression 's|^pruning-keep-recent =.*|pruning-keep-recent = 10000|' \
            --expression '/^\[state-sync]/,/^\[/{s|^snapshot-interval =.*|snapshot-interval = 1000|}' \
            --expression '/^\[state-sync]/,/^\[/{s|^snapshot-keep-recent =.*|snapshot-keep-recent = 10|}' \
            --in-place
    fi

    sed "$AGORIC_HOME/config/app.toml" \
        --expression '/^\[api]/,/^\[/{s|^address =.*|address = "tcp://0.0.0.0:1317"|}' \
        --expression '/^\[api]/,/^\[/{s|^enable =.*|enable = true|}' \
        --expression '/^\[api]/,/^\[/{s|^enabled-unsafe-cors =.*|enabled-unsafe-cors = true|}' \
        --expression '/^\[api]/,/^\[/{s|^max-open-connections =.*|max-open-connections = 1000|}' \
        --expression '/^\[api]/,/^\[/{s|^swagger =.*|swagger = false|}' \
        --expression '/^\[rosetta]/,/^\[/{s|^enable =.*|enable = false|}' \
        --expression '/^\[telemetry]/,/^\[/{s|^enabled =.*|enabled = true|}' \
        --expression '/^\[telemetry]/,/^\[/{s|^laddr =.*|laddr = "tcp://0.0.0.0:26652"|}' \
        --expression '/^\[telemetry]/,/^\[/{s|^prometheus-retention-time =.*|prometheus-retention-time = 60|}' \
        --expression 's|^rpc-max-body-bytes =.*|rpc-max-body-bytes = \"15000000\"|' \
        --in-place

    sed "$AGORIC_HOME/config/config.toml" \
        --expression 's|^addr_book_strict =.*|addr_book_strict = false|' \
        --expression 's|^allow_duplicate_ip =.*|allow_duplicate_ip = true|' \
        --expression 's|^log_level|# log_level|' \
        --expression "s|^max_num_inbound_peers =.*|max_num_inbound_peers = $MAXIMUM_INBOUND_PEERS|" \
        --expression "s|^max_num_outbound_peers =.*|max_num_outbound_peers = $MAXIMUM_OUTBOUND_PEERS|" \
        --expression 's|^namespace =.*|namespace = "cometbft"|' \
        --expression 's|^prometheus = false|prometheus = true|' \
        --expression "/^\[rpc]/,/^\[/{s|^laddr =.*|laddr = 'tcp://0.0.0.0:$RPC_PORT'|}" \
        --in-place
}

update_swingset_config_file() {
    local addr1
    local addr2
    local addr3
    local current_config
    local resolved_config="$1"

    current_config="$(cat "$resolved_config")"

    if test -n "$ENDORSED_UI"; then
        current_config="$(
            echo "$current_config" |
                sed --expression "s|bafybeidvpbtlgefi3ptuqzr2fwfyfjqfj6onmye63ij7qkrb4yjxekdh3e|$ENDORSED_UI|"
        )"
    fi

    if test -n "$GC_INTERVAL"; then
        current_config="$(
            echo "$current_config" |
                jq --arg "freq" "$GC_INTERVAL" '. + {defaultReapInterval: ($freq | tonumber)}'
        )"
    fi

    if test -n "$PSM_GOV_A"; then
        addr1="$(
            echo "$PSM_GOV_A" |
                add_key "econ" --dry-run --output "json" --recover |
                jq --raw-output '.address'
        )"
        addr2="$(
            echo "$PSM_GOV_B" |
                add_key "econ" --dry-run --output "json" --recover |
                jq --raw-output '.address'
        )"
        addr3="$(
            echo "$PSM_GOV_C" |
                add_key "econ" --dry-run --output "json" --recover |
                jq --raw-output '.address'
        )"

        current_config="$(
            echo "$current_config" |
                jq --arg "addr1" "$addr1" --arg "addr2" "$addr2" --arg "addr3" "$addr3" \
                    '.vats.bootstrap.parameters.economicCommitteeAddresses? |= {"gov1": $addr1, "gov2": $addr2, "gov3": $addr3}'
        )"
    fi

    echo -E "$current_config" >"$resolved_config"
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

wait_for_url() {
    local url="$1"
    local status_code

    echo "Waiting for url '$url' to respond"

    while true; do
        curl "$url" --max-time "5" --silent >"$VOID" 2>&1
        status_code="$?"

        echo "URL '$url' responded with '$status_code'"

        if ! test "$status_code" -eq "0"; then
            sleep 5
        else
            break
        fi
    done

    echo "URL '$url' is up"
}

wait_till_syncup_and_fund() {
    local response=""
    local stakeamount="400000000ibc/toyusdc"
    local wallet_name="$1"

    while true; do
        if has_node_caught_up; then
            sleep 30
            response="$(
                agd tx bank send "$wallet_name" "$PROVISIONING_ADDRESS" "$stakeamount" \
                    --broadcast-mode "block" \
                    --chain-id "$CHAIN_ID" \
                    --home "$AGORIC_HOME" \
                    --keyring-backend "test" \
                    --node "$PRIMARY_VALIDATOR_SERVICE_URL:$RPC_PORT" \
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
        sleep 5
    done
}

wait_till_syncup_and_register() {
    local moniker="${2:-"$PODNAME"}"
    local delegation_wallet_name="self"
    local pub_key=""
    local stake_amount="50000000ubld"
    local validator_address=""
    local wallet_name="$1"

    local validator_json_path="/tmp/$moniker"

    local create_validator_args=("$validator_json_path")

    validator_address="$(
        agd keys show "$delegation_wallet_name" --address --bech "val" --home "$AGORIC_HOME" --keyring-backend "test" 2>"$VOID"
    )"

    while true; do
        if has_node_caught_up; then
            if test -n "$validator_address"; then
                if ! agd query staking validator "$validator_address" --home "$AGORIC_HOME" >"$VOID" 2>&1; then
                    echo "caught up, register validator"
                    ensure_balance "$wallet_name" "$stake_amount"
                    sleep 10

                    pub_key="$(agd tendermint show-validator --home "$AGORIC_HOME")"
                    jq '
                        {
                            "amount": $amount,
                            "commission-max-rate": "0.20",
                            "commission-max-change-rate": "0.01",
                            "commission-rate": "0.10",
                            "details": "",
                            "min-self-delegation": "1",
                            "moniker": $moniker,
                            "pubkey": {
                                "@type": $pub_key_type,
                                "key": $pub_key_value
                            },
                            "website": $website
                        }
                    ' \
                    --arg "amount" "$stake_amount" \
                    --arg "moniker" "$moniker" \
                    --arg "pub_key_type" "$(echo "$pub_key" | jq '."@type"' --raw-output)" \
                    --arg "pub_key_value" "$(echo "$pub_key" | jq '.key' --raw-output)" \
                    --arg "website" "http://$POD_IP:$RPC_PORT" \
                    --null-input \
                    --raw-output > "$validator_json_path"

                    if semver_comparison "$(get_agd_sdk_version)" "$LESS_THAN_COMPARATOR" "$(echo "$SDK_VERSIONS" | jq '."0.50.14"' --raw-output)"; then
                        local validator_data="$(jq --raw-output < "$validator_json_path")"
                        create_validator_args=(
                            "--amount"
                            "$(echo "$validator_data" | jq '.amount' --raw-output)"
                            "--commission-max-change-rate"
                            "$(echo "$validator_data" | jq '."commission-max-change-rate"' --raw-output)"
                            "--commission-max-rate"
                            "$(echo "$validator_data" | jq '."commission-max-rate"' --raw-output)"
                            "--commission-rate"
                            "$(echo "$validator_data" | jq '."commission-rate"' --raw-output)"
                            "--details"
                            "$(echo "$validator_data" | jq '.details' --raw-output)"
                            "--min-self-delegation"
                            "$(echo "$validator_data" | jq '."min-self-delegation"' --raw-output)"
                            "--moniker"
                            "$(echo "$validator_data" | jq '.moniker' --raw-output)"
                            "--pubkey"
                            "$pub_key"
                            "--website"
                            "$(echo "$validator_data" | jq '.website' --raw-output)"
                        )
                    fi

                    agd tx staking create-validator "${create_validator_args[@]}" \
                        --chain-id "$CHAIN_ID" \
                        --from "$delegation_wallet_name" \
                        --gas "auto" \
                        --gas-adjustment "1.4" \
                        --home "$AGORIC_HOME" \
                        --keyring-backend "test" \
                        --node "$PRIMARY_VALIDATOR_SERVICE_URL:$RPC_PORT" \
                        --yes
                    rm --force "$validator_json_path"
                    touch "$AGORIC_HOME/registered"

                    sleep 10
                else
                    echo "Current node is already a validator (address: '$validator_address')"
                fi
            else
                echo "Wallet '$delegation_wallet_name' not found"
            fi
            break
        else
            echo "not caught up, waiting to register validator"
        fi
        sleep 5
    done
}
