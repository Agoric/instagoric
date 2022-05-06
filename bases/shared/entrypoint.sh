#!/bin/bash
set -x
set +e

export PRIMARY_ENDPOINT="http://validator-primary.$NAMESPACE.svc.cluster.local"
export RPC_ENDPOINT="http://rpcnodes.$NAMESPACE.svc.cluster.local"
export ENDPOINT="http://validator.$NAMESPACE.svc.cluster.local"
export WHALE_KEYNAME="whale"
export CHAIN_ID=${CHAIN_ID:-instagoric-1}
export AGORIC_HOME="/state/$CHAIN_ID"
boottime="$(date '+%s')"
export SLOGFILE="/state/slogfile_${boottime}.json"
export AG_SOLO_BASEDIR="/state/$CHAIN_ID-solo"
export WHALE_SECRET="${WHALE_SECRET:-chuckle good seminar twin parrot split minimum humble tumble predict liberty taste match blossom vicious pride slogan supreme attract lucky typical until switch dry}"
export BOOTSTRAP_CONFIG=${BOOTSTRAP_CONFIG:-"@agoric/vats/decentral-demo-config.json"}
export VOTING_PERIOD=${VOTING_PERIOD:-18h}
export WHALE_DERIVATIONS=${WHALE_DERIVATIONS:-20}

mkdir -p /state/cores
chmod a+rwx /state/cores
echo "/state/cores/core.%e.%p.%h.%t" > /proc/sys/kernel/core_pattern


primary_node_peer () {
    echo "fb86a0993c694c981a28fa1ebd1fd692f345348b"
}

primary_genesis () {
    while true; do
        if json=$(curl -m 15 -sS "$PRIMARY_ENDPOINT:8001/genesis.json"); then 
            echo "$json"
            break
        fi
        sleep 2
    done
}
wait_for_bootstrap () {
    endpoint="${RPC_ENDPOINT}"
    while true; do
        if json=$(curl -m 15 -sS "$endpoint:26657/status"); then 
            if [[ "$(echo "$json" | jq -r .jsonrpc)" == "2.0" ]]; then 
                if last_height=$(echo "$json" | jq -r .result.sync_info.latest_block_height); then
                    if [[ "$last_height" != "1" ]]; then
                        echo "Chain alive!"
                        return
                    else
                        echo "Last Height: $last_height"
                    fi
                fi
            fi
        fi
        sleep 2
    done
}

add_whale_key () {
    keynum=${1:-0}
    echo $WHALE_SECRET | agd keys add "${WHALE_KEYNAME}_${keynum}" --index $keynum --recover --home "$AGORIC_HOME"  --keyring-backend test
}

create_self_key () {
    agd keys add self --home "$AGORIC_HOME" --keyring-backend test > /state/self.out 2>&1
    tail -n1 /state/self.out > /state/self.key
    key_address=$(agd keys show self -a --home "$AGORIC_HOME" --keyring-backend test)
    echo "$key_address" > /state/self.address
}

create_self_solo_key () {
    address_file="/state/self.key"
    if [ -f "$address_file" ]; then
        return
    fi
    cat $AG_SOLO_BASEDIR/ag-solo-mnemonic | agd keys add self --recover --home "$AGORIC_HOME" --keyring-backend test
    cp $AG_SOLO_BASEDIR/ag-solo-mnemonic /state/self.key
    key_address=$(agd keys show self -a --home "$AGORIC_HOME" --keyring-backend test)
    echo "$key_address" > /state/self.address
}

tell_primary_about_validator () {
    while true; do
        if status=$(agd status --home="$AGORIC_HOME"); then
            break
        fi
        echo "node not yet up, waiting to register"
        sleep 5
    done
    echo "Node Up"

    node_id=$(agd tendermint show-node-id --home "$AGORIC_HOME")
    dial_result=$(curl -m 15 -sS -g "$PRIMARY_ENDPOINT:26657/dial_peers?peers=[\"$node_id@$POD_IP:26656\"]&persistent=true&private=false")
    echo "Dialed Primary: $dial_result"

}

get_whale_index () {
    podnum=$(echo $PODNAME | grep -o '[0-9]*$')
    validator_padding=20
    ag_solo_manual_padding=10
    case $PODNAME in
        validator-primary-*)
            echo 0
            return
            ;;
        validator-*)
            echo "$((1+podnum))"
            return
            ;;
        ag-solo-manual-*)
            echo "$((validator_padding+podnum))"
            return
            ;;
        ag-solo-tasks-*)
            echo "$((validator_padding+ag_solo_manual_padding+podnum))"
            return
            ;;
    esac
}
get_whale_keyname () {
    idx=$(get_whale_index)
    echo "${WHALE_KEYNAME}_${idx}"
}

solo_addr () {
    address_file="$AG_SOLO_BASEDIR/ag-cosmos-helper-address"
    while true; do
        if [ -f "$address_file" ]; then
            cat $address_file
            break
        fi
        sleep 1
    done
}

fund_solo () {
    echo "funding solo"
    address="$(solo_addr)"
    create_self_solo_key
    amount=${1:-"50000000urun"}
    send_coin "$(get_whale_keyname)" "$amount" "$address"
    while true; do
        if agd tx swingset provision-one "${PODNAME}-ag-solo" "$address" -y --home "$AGORIC_HOME" --keyring-backend test --from self --node "${RPC_ENDPOINT}:26657" -y --chain-id="$CHAIN_ID"; then
            touch "$AG_SOLO_BASEDIR/funded"
            return
        fi
        sleep $(( ( RANDOM % 4 )  + 1 ))
    done
}

run_tasks () {
    cd /usr/src/agoric-sdk || exit
    mkdir ag-solo-tasks
    cd ag-solo-tasks || exit
    cp /tasks/* .
    while true; do
        if agoric deploy loaded.js; then
            echo "ag-solo loaded"
            break
        fi
        echo "ag-solo not finished loading"
        sleep 2
    done

    while true; do
        agoric deploy amm_swap.js
        sleep 1
    done
}

wait_till_syncup_and_register () {
    while true; do
        if status=$(agd status --home="$AGORIC_HOME"); then
            if parsed=$(echo "$status" | jq -r .SyncInfo.catching_up); then
                if [[ $parsed == "false" ]]; then
                    echo "caught up, register validator"
                    stakeamount="50000000ubld"
                    send_coin "$(get_whale_keyname)" "$stakeamount"
                    sleep 10
                    agd tx staking create-validator \
  --home="$AGORIC_HOME" \
  --amount="${stakeamount}" \
  --pubkey="$(agd tendermint show-validator  --home=$AGORIC_HOME)" \
  --moniker="$PODNAME" \
  --website="http://$POD_IP:26657" \
  --details="" \
  --node="http://localhost:26657" \
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
                return
                else
                    echo "not caught up, waiting to register validator"
                fi
            fi
        fi
        sleep 5
    done
}

send_coin () {
    from=$1
    amount=$2
    to=${3:-$(cat /state/self.address)}
    
    while true; do
        pre=$(agd query bank balances $to --node http://rpcnodes.$NAMESPACE.svc.cluster.local:26657 | md5sum | awk '{ print $1 }' )
        while true; do
            if agd tx bank send -b block "$from" "$to" "${amount}" --node "${PRIMARY_ENDPOINT}:26657" -y --keyring-backend=test --home="$AGORIC_HOME"  --chain-id="$CHAIN_ID"; then
                echo "successfully sent $amount to $to"
                break
            fi
        done
        sleep 10
        post=$(agd query bank balances $to --node http://rpcnodes.$NAMESPACE.svc.cluster.local:26657 | md5sum | awk '{ print $1 }' )
        if [[ "$pre" != "$post" ]]; then
            echo "coin sent"
            break
        fi
        echo "error sending coin, retrying"
        sleep $(( ( RANDOM % 50 )  + 1 ))
    done
}
start_helper () {
    while true; do
        node "/server/server.js"
        sleep 1
    done
}

start_chain () {
    # shellcheck disable=SC2068
    agd start --home="$AGORIC_HOME" --log_format=json $@ 2>&1 | tee -a /state/app.log
}
hang () {
    while true; do sleep 30; done
}


get_ips() {
    servicename=$1
    while true; do
        if json=$(curl -m 15 -sS "localhost:8001/ips"); then 
            if [[ "$(echo "$json" | jq -r .status)" == "1" ]]; then 
                if ip=$(echo "$json" | jq -r ".ips.\"$servicename\""); then
                    echo "$ip"
                    break
                fi
            fi
        fi

        sleep 2;
    done
}

###
if [[ -z "${ENABLE_TELEMETRY}" ]]; then
  echo "skipping telemetry since ENABLE_TELEMETRY is not set"
  unset OTEL_EXPORTER_OTLP_ENDPOINT
  unset OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
elif [[ -f "${USE_OTEL_CONFIG}" ]]; then
  echo "starting telemetry collector"
  OTEL_CONFIG="$HOME/instagoric-otel-config.yaml"
  cp "${USE_OTEL_CONFIG}" "$OTEL_CONFIG"
  sed -i.bak -e "s/@HONEYCOMB_API_KEY@/${HONEYCOMB_API_KEY}/" \
    -e "s/@HONEYCOMB_DATASET@/${HONEYCOMB_DATASET}/" \
    "$HOME/instagoric-otel-config.yaml"
  /usr/local/bin/otelcol-contrib --config "$OTEL_CONFIG" &
fi


echo "ROLE: $ROLE"
echo "whale keyname: $(get_whale_keyname)"
firstboot="false"
if [[ $ROLE == "ag-solo" ]]; then
    if [[ ! -f "$AG_SOLO_BASEDIR/ag-solo-mnemonic" ]] || [[ ! -f "$AG_SOLO_BASEDIR/funded" ]]; then
        #ag-solo firstboot
        firstboot="true"
    fi
else
    #agd firstboot
    if [[ -n "${GC_INTERVAL}" ]]; then      
        jq '. + {defaultReapInterval: $freq}' --arg freq $GC_INTERVAL /usr/src/agoric-sdk/packages/vats/decentral-demo-config.json > /usr/src/agoric-sdk/packages/vats/decentral-demo-config-modified.json
        jq '. + {defaultReapInterval: $freq}' --arg freq $GC_INTERVAL /usr/src/agoric-sdk/packages/vats/decentral-demo-config.json > /usr/src/agoric-sdk/node_modules/\@agoric/vats/decentral-demo-config-modified.json
        export BOOTSTRAP_CONFIG="@agoric/vats/decentral-demo-config-modified.json"
    fi

    if [[ ! -f "$AGORIC_HOME/config/config.toml" ]]; then
        # ari's terrible docker fix, please eventually remove
        apt-get install -y nano tmux netcat

        firstboot="true"
        echo "Initializing chain"
        agd init --home "$AGORIC_HOME" --chain-id "$CHAIN_ID" "$PODNAME"
        agoric set-defaults ag-chain-cosmos $AGORIC_HOME/config

        # Preserve the node key for this state.
        if [[ ! -f /state/node_key.json ]]; then
          cp "$AGORIC_HOME/config/node_key.json" /state/node_key.json
        fi
        cp /state/node_key.json "$AGORIC_HOME/config/node_key.json"

        if [[ $ROLE == "validator-primary" ]]; then
            if [[ -n "${GC_INTERVAL}" ]] && [[ -n "$HONEYCOMB_API_KEY" ]]; then      
                timestamp=$(date +%s)
                curl "https://api.honeycomb.io/1/markers/$HONEYCOMB_DATASET" -X POST  \
                    -H "X-Honeycomb-Team: $HONEYCOMB_API_KEY"  \
                    -d "{\"message\":\"GC_INTERVAL: ${GC_INTERVAL}\", \"type\":\"deploy\", \"start_time\":${timestamp}}"
            fi

            create_self_key
            agd add-genesis-account self 50000000ubld --keyring-backend test --home "$AGORIC_HOME" 
            

            for ((i=0; i <= $WHALE_DERIVATIONS; i++)); do 
                add_whale_key $i
                agd add-genesis-account "${WHALE_KEYNAME}_${i}" 10000000000000000ubld,10000000000000000urun,1000000provisionpass --keyring-backend test --home "$AGORIC_HOME" 
            done
            #faucet
            agd add-genesis-account agoric1hr29lkgsdzdr0jdpa0tfzjgrm0vnd339qde52l 10000000000000000ubld,10000000000000000urun,1000000provisionpass,100000000000000000000000000ibc/0123456789abcdef,2000000000000ibc/123456789abcdef0,4000000000000ibc/23456789abcdef01,8000000000000ibc/3456789abcdef012 --keyring-backend test --home "$AGORIC_HOME" 
            
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
            
            
            contents="$(jq ".app_state.swingset.params.bootstrap_vat_config = \"$BOOTSTRAP_CONFIG\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" > $AGORIC_HOME/config/genesis.json
            contents="$(jq ".app_state.gov.voting_params.voting_period = \"$VOTING_PERIOD\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" > $AGORIC_HOME/config/genesis.json
            cp $AGORIC_HOME/config/genesis.json $AGORIC_HOME/config/genesis_final.json 

        else
            primary_genesis > $AGORIC_HOME/config/genesis.json
        fi
        sed -i.bak 's/^log_level/# log_level/' "$AGORIC_HOME/config/config.toml"
        sed -i.bak 's/^prometheus = false/prometheus = true/' "$AGORIC_HOME/config/config.toml"
        sed -i.bak 's/^addr_book_strict = true/addr_book_strict = false/' "$AGORIC_HOME/config/config.toml"
        sed -i.bak 's/^max_num_inbound_peers =.*/max_num_inbound_peers = 150/' "$AGORIC_HOME/config/config.toml"
        sed -i.bak 's/^max_num_outbound_peers =.*/max_num_outbound_peers = 150/' "$AGORIC_HOME/config/config.toml"
        sed -i.bak '/^\[telemetry]/,/^\[/{s/^laddr[[:space:]]*=.*/laddr = "tcp:\/\/0.0.0.0:26652"/}' "$AGORIC_HOME/config/app.toml"
        sed -i.bak '/^\[telemetry]/,/^\[/{s/^prometheus-retention-time[[:space:]]*=.*/prometheus-retention-time = 60/}' "$AGORIC_HOME/config/app.toml"
        sed -i.bak '/^\[api]/,/^\[/{s/^enable[[:space:]]*=.*/enable = true/}' "$AGORIC_HOME/config/app.toml"
        sed -i.bak '/^\[api]/,/^\[/{s/^swagger[[:space:]]*=.*/swagger = false/}' "$AGORIC_HOME/config/app.toml"
        sed -i.bak '/^\[api]/,/^\[/{s/^address[[:space:]]*=.*/address = "tcp:\/\/0.0.0.0:1317"/}' "$AGORIC_HOME/config/app.toml"
        sed -i.bak '/^\[api]/,/^\[/{s/^max-open-connections[[:space:]]*=.*/max-open-connections = 1000/}' "$AGORIC_HOME/config/app.toml"
        sed -i.bak '/^\[rpc]/,/^\[/{s/^laddr[[:space:]]*=.*/laddr = "tcp:\/\/0.0.0.0:26657"/}' "$AGORIC_HOME/config/config.toml"
    fi
fi
(start_helper &)
echo "Firstboot: $firstboot"
case "$ROLE" in
    "validator-primary")
        if [[ $firstboot == "true" ]]; then
            cp /config/network/node_key.json "$AGORIC_HOME/config/node_key.json"
        fi
        
        # external_address=$(get_ips validator-primary-ext)
        # sed -i.bak "s/^external_address =.*/external_address = \"$external_address:26656\"/" "$AGORIC_HOME/config/config.toml"
        export XSNAP_TEST_RECORD="${AGORIC_HOME}/xs_test_record_${boottime}"
        export DEBUG="agoric,SwingSet:ls,SwingSet:vat"
        start_chain
        ;;

    "validator")
        # wait for network live
        if [[ $firstboot == "true" ]]; then
            add_whale_key "$(get_whale_index)"
            create_self_key
            #wait_for_bootstrap
            # get primary peer id
            primary=$(primary_node_peer)
            PEERS="$primary@validator-primary.$NAMESPACE.svc.cluster.local:26656"
            sed -i.bak -e "s/^seeds =.*/seeds = \"$SEEDS\"/; s/^persistent_peers =.*/persistent_peers = \"$PEERS\"/" "$AGORIC_HOME/config/config.toml"
            sed -i.bak "s/^unconditional_peer_ids =.*/unconditional_peer_ids = \"$primary\"/" "$AGORIC_HOME/config/config.toml"
            sed -i.bak "s/^persistent_peers_max_dial_period =.*/persistent_peers_max_dial_period = \"3s\"/" "$AGORIC_HOME/config/config.toml"
        fi
        if [[ ! -f "$AGORIC_HOME/registered" ]]; then
            ( wait_till_syncup_and_register ) &
        fi
        export XSNAP_TEST_RECORD="${AGORIC_HOME}/xs_test_record_${boottime}"
        export DEBUG="agoric,SwingSet:ls,SwingSet:vat"

        start_chain
        ;;
    "ag-solo")
        if [[ $firstboot == "true" ]]; then
            add_whale_key "$(get_whale_index)"
            
            wait_for_bootstrap
            (fund_solo "${SOLO_FUNDING_AMOUNT:-"500000000000urun,500000000000ubld,1provisionpass"}") &
            agoric open --repl | tee "/state/agoric.repl"
            cp /config/network/network_info.json /state/network_info.json
            contents="$(jq ".chainName = \"$CHAIN_ID\"" /state/network_info.json)" && echo -E "${contents}" > /state/network_info.json
        fi

        wait_for_bootstrap
        if [[ $SUBROLE == "tasks" ]]; then
            ( sleep 60 && run_tasks ) &
        fi

        ag-solo setup --netconfig=file:///state/network_info.json --webhost=0.0.0.0 2>&1 | tee -a /state/app.log
        ;;
    "seed")
        if [[ $firstboot == "true" ]]; then
            create_self_key
            # wait for network live

            cp /config/network/seed_node_key.json "$AGORIC_HOME/config/node_key.json"
            # get primary peer id
            primary=$(primary_node_peer)
            PEERS="$primary@validator-primary.$NAMESPACE.svc.cluster.local:26656"

            sed -i.bak -e "s/^seeds =.*/seeds = \"$SEEDS\"/; s/^persistent_peers =.*/persistent_peers = \"$PEERS\"/" "$AGORIC_HOME/config/config.toml"
            sed -i.bak "s/^unconditional_peer_ids =.*/unconditional_peer_ids = \"$primary\"/" "$AGORIC_HOME/config/config.toml"
            sed -i.bak "s/^seed_mode =.*/seed_mode = true/" "$AGORIC_HOME/config/config.toml"
        fi
        external_address=$(get_ips seed-ext)
        sed -i.bak "s/^external_address =.*/external_address = \"$external_address:26656\"/" "$AGORIC_HOME/config/config.toml"

        start_chain --pruning everything
        ;;
    *)
        echo "unknown role"
        exit 1
        ;;
esac

if [ -f "/state/hang" ]; then
    hang
fi