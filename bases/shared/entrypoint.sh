#!/bin/bash
set -x
set +e

#use of primary is required for bootstrapping, as rpcnodes may be serving nodes of various registration states during early bootup
export PRIMARY_ENDPOINT="http://validator-primary.$NAMESPACE.svc.cluster.local"
export RPC_ENDPOINT="http://rpcnodes.$NAMESPACE.svc.cluster.local"
export ENDPOINT="http://validator.$NAMESPACE.svc.cluster.local"
export WHALE_KEYNAME="whale"
export CHAIN_ID=${CHAIN_ID:-instagoric-1}
export AGORIC_HOME="/state/$CHAIN_ID"
boottime="$(date '+%s')"
export SLOGFILE="/state/slogfile_${boottime}.json"
export AG_SOLO_BASEDIR="/state/$CHAIN_ID-solo"
export BOOTSTRAP_CONFIG=${BOOTSTRAP_CONFIG:-"@agoric/vats/decentral-demo-config.json"}
export VOTING_PERIOD=${VOTING_PERIOD:-18h}
export WHALE_DERIVATIONS=${WHALE_DERIVATIONS:-100}
export MODIFIED_BOOTSTRAP_PATH="/usr/src/agoric-sdk/packages/vats/modified-bootstrap.json"
export SWINGSTORE="$AGORIC_HOME/data/agoric/swingstore.sqlite"
mkdir -p $AGORIC_HOME
if [[ -z "$AG0_MODE" ]]; then 
version=$(cat /usr/src/agoric-sdk/packages/solo/public/git-revision.txt | tr '\n' ' ' )
else
version=ag0
fi
export DD_VERSION="$version"
export DD_ENV=$CHAIN_ID
export DD_SERVICE="agd"
export DD_AGENT_HOST=datadog.datadog.svc.cluster.local

export MAINFORK_HEIGHT=12838002
export MAINFORK_IMAGE_URL="https://storage.googleapis.com/agoric-snapshots-public/mainfork-snapshots"

# Kubernetes API constants
API_ENDPOINT=https://kubernetes.default.svc
TOKEN_PATH=/var/run/secrets/kubernetes.io/serviceaccount/token
CA_PATH=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
NAMESPACE_PATH=/var/run/secrets/kubernetes.io/serviceaccount/namespace
NAMESPACE=$(cat $NAMESPACE_PATH)
TOKEN=$(cat $TOKEN_PATH)

mkdir -p /state/cores
chmod a+rwx /state/cores
echo "/state/cores/core.%e.%p.%h.%t" > /proc/sys/kernel/core_pattern

ln -sf "$SLOGFILE" /state/slogfile_current.json


export MAX_VATS=70

generate_process_metrics_exporter_config() {
    mkdir -p /config/process-metrics
    echo "process_names:" > /config/process-metrics/config.yaml
    for i in $(seq 1 $MAX_VATS); do
      echo "  - name: \"v$i\""
      echo "    cmdline:"
      echo "    - \".* v$i:.*\""
      echo ""
    done >> /config/process-metrics/config.yaml
}

start_process_metrics_exporter () {
    (
      while true; do
        prometheus-process-exporter -config.path /config/process-metrics/config.yaml >> /state/process-exporter.log 2>&1
        sleep 120
      done
    )
}

generate_process_metrics_exporter_config
apt-get install -y prometheus-process-exporter
start_process_metrics_exporter &

install_store_stats_exporter() {
    mkdir -p $HOME/store-stats
    cp /config/store-stats/* $HOME/store-stats
    cd $HOME/store-stats
    yarn install
}

start_store_metrics_exporter () {
    (
      cd $HOME/store-stats
      while true; do
        node store-stats.js $SWINGSTORE >> /state/store-stats-exporter.log 2>&1
        sleep 120
      done
    )
}

install_store_stats_exporter
start_store_metrics_exporter &

ag_binary () {
    if [[ -z "$AG0_MODE" ]]; then 
        echo "agd";
    else
        echo "ag0";
    fi
}
primary_node_peer () {
    echo "fb86a0993c694c981a28fa1ebd1fd692f345348b"
}
seed_node_peer () {
    echo "0f04c4610b7511a64b8644944b907416db568590"
}

primary_genesis () {
    while true; do
        if json=$(curl --fail -m 15 -sS "$PRIMARY_ENDPOINT:8002/genesis.json"); then 
            echo "$json"
            break
        fi
        sleep 2
    done
}
wait_for_bootstrap () {
    endpoint="${PRIMARY_ENDPOINT}"
    while true; do
        if json=$(curl --fail -m 15 -sS "$endpoint:26657/status"); then 
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
    [[ -n "$WHALE_SEED" ]] || return 1
    echo "$WHALE_SEED" | $(ag_binary) keys add "${WHALE_KEYNAME}_${keynum}" --index "$keynum" --recover --home "$AGORIC_HOME"  --keyring-backend test
}

create_self_key () {
    $(ag_binary) keys add self --home "$AGORIC_HOME" --keyring-backend test > /state/self.out 2>&1
    tail -n1 /state/self.out > /state/self.key
    key_address=$($(ag_binary) keys show self -a --home "$AGORIC_HOME" --keyring-backend test)
    echo "$key_address" > /state/self.address
}

ensure_self_solo_key () {
    key_file=/state/self.key
    if [ -f "$key_file" ]; then
        if ! $(ag_binary) keys show self --home "$AGORIC_HOME" --keyring-backend=test; then
            < "$key_file" $(ag_binary) keys add self --recover --home "$AGORIC_HOME" --keyring-backend test
        fi
        return
    fi
    < "$AG_SOLO_BASEDIR/ag-solo-mnemonic" $(ag_binary) keys add self --recover --home "$AGORIC_HOME" --keyring-backend test
    cp "$AG_SOLO_BASEDIR/ag-solo-mnemonic" /state/self.key
    key_address=$($(ag_binary) keys show self -a --home "$AGORIC_HOME" --keyring-backend test)
    echo "$key_address" > /state/self.address
}

tell_primary_about_validator () {
    while true; do
        if status=$($(ag_binary) status --home="$AGORIC_HOME"); then
            break
        fi
        echo "node not yet up, waiting to register"
        sleep 5
    done
    echo "Node Up"

    node_id=$($(ag_binary) tendermint show-node-id --home "$AGORIC_HOME")
    dial_result=$(curl --fail -m 15 -sS -g "$PRIMARY_ENDPOINT:26657/dial_peers?peers=[\"$node_id@$POD_IP:26656\"]&persistent=true&private=false")
    echo "Dialed Primary: $dial_result"

}

get_whale_index () { 
    name=${1:-$PODNAME}
    podnum=$(echo "$name" | grep -o '[0-9]*$')
    validator_padding=20
    ag_solo_manual_padding=10
    case $name in
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
            cat "$address_file"
            break
        fi
        sleep 1
    done
}

ensure_solo_provisioned () {
    address="$(solo_addr)"
    echo "provisioning solo $address"
    ensure_self_solo_key
    amount=${1:-"500000000000000uist"}
    whale_key=$(get_whale_keyname)
    ensure_balance "$whale_key" "$amount" "$address"
    while ! $(ag_binary) query swingset egress "$address" --node="$PRIMARY_ENDPOINT:26657"; do
        $(ag_binary) tx swingset provision-one "$PODNAME" "$address" \
          -y --home "$AGORIC_HOME" --keyring-backend test --from self \
          --node "${PRIMARY_ENDPOINT}:26657" -y --chain-id="$CHAIN_ID" -b block
        sleep $(( ( RANDOM % 4 )  + 10 ))
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
        if status=$($(ag_binary) status --home="$AGORIC_HOME"); then
            if parsed=$(echo "$status" | jq -r .SyncInfo.catching_up); then
                if [[ $parsed == "false" ]]; then
                    echo "caught up, register validator"
                    stakeamount="50000000ubld"
                    ensure_balance "$(get_whale_keyname)" "$stakeamount"
                    sleep 10
                    $(ag_binary) tx staking create-validator \
  --home="$AGORIC_HOME" \
  --amount="${stakeamount}" \
  --pubkey="$($(ag_binary) tendermint show-validator  --home=$AGORIC_HOME)" \
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


wait_till_syncup_and_fund () {
    if [[ -z "$AG0_MODE" ]]; then 
        while true; do
            if status=$($(ag_binary) status --home="$AGORIC_HOME"); then
                if parsed=$(echo "$status" | jq -r .SyncInfo.catching_up); then
                    if [[ $parsed == "false" ]]; then
                        if [[ $DD_PROFILING_ENABLED == "true" ]]; then
                            sleep 300
                        else
                            sleep 30
                        fi
                        stakeamount="400000000ibc/toyusdc"

                        $(ag_binary) tx bank send -b block "$(get_whale_keyname)" "agoric1megzytg65cyrgzs6fvzxgrcqvwwl7ugpt62346" "$stakeamount" \
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
    fi 

}





ensure_balance () {
    from=$1
    amount=$2
    to=${3:-$(cat /state/self.address)}
    
    want=${amount//,/ }
    while true; do
        have=$($(ag_binary) query bank balances "$to" --node "$PRIMARY_ENDPOINT:26657" -ojson | jq -r '.balances')
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
        if $(ag_binary) tx bank send -b block "$from" "$to" "$needed" \
          --node "${PRIMARY_ENDPOINT}:26657" -y --keyring-backend=test \
          --home="$AGORIC_HOME" --chain-id="$CHAIN_ID"; then
            echo "successfully sent $amount to $to"
        else
            sleep $(( ( RANDOM % 50 ) + 10 ))
        fi
    done
}
start_helper () {
    (
      SRV=/usr/src/instagoric-server
      rm -rf "$SRV"
      mkdir -p "$SRV" || exit
      cp /config/server/* "$SRV" || exit
      cd "$SRV" || exit
      yarn --production
      while true; do
        yarn start >> /state/server.log 2>&1 
        sleep 1
      done
    )
}

start_chain () {
    # shellcheck disable=SC2068
    if [[ -z "$AG0_MODE" ]]; then 
        extra=""
        if [[ "$DD_PROFILING_ENABLED" == "true" ]]; then
            extra=" -r dd-trace/init"
            #export SWINGSET_WORKER_TYPE=local
        fi
        (cd /usr/src/agoric-sdk && node $extra /usr/local/bin/ag-chain-cosmos --home "$AGORIC_HOME" start --log_format=json $@  >> /state/app.log 2>&1)
    else
        $(ag_binary) start --home="$AGORIC_HOME" --log_format=json $@ >> /state/app.log 2>&1 
    fi
}
hang () {
    while true; do sleep 30; done
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

        sleep 2;
    done
}

get_pod_ip() {
    # Define your variable
    APP_LABEL_VALUE=$1

    while true; do
        POD_INFO=$(curl -sSk -H "Authorization: Bearer $TOKEN" --cacert $CA_PATH $API_ENDPOINT/api/v1/namespaces/$NAMESPACE/pods/)
        POD_IP=$(echo "$POD_INFO" | jq --arg app_value "$APP_LABEL_VALUE" -r '.items[] | select(.metadata.labels.app == $app_value) .status.podIP')
    
        if [[ -z "$POD_IP" ]]; then
            echo "Couldn't get Pod IP address. Trying again..."
        else
            break
        fi
        sleep 10
    done

    echo "$POD_IP"
}

wait_for_pod() {
    # Define your variable
    APP_LABEL_VALUE=$1

    while true; do
        POD_INFO=$(curl -sSk -H "Authorization: Bearer $TOKEN" --cacert $CA_PATH $API_ENDPOINT/api/v1/namespaces/$NAMESPACE/pods/)
        POD_PHASE=$(echo "$POD_INFO" | jq --arg app_value "$APP_LABEL_VALUE" -r '.items[] | select(.metadata.labels.app == $app_value) .status.phase')
    
        if [[ "$POD_PHASE" != "Running" ]]; then
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

    mkdir -p $AGORIC_HOME
    rm -rf $AGORIC_HOME/*

    if [ ! -f "$MAINFORK_IMAGE_URL/$THIS_FORK-config-$MAINFORK_HEIGHT.tar.gz" ]; then
        apt install -y axel
        axel --quiet -n 10 -o "/state/$THIS_FORK-config-$MAINFORK_HEIGHT.tar.gz" "$MAINFORK_IMAGE_URL/$THIS_FORK-config-$MAINFORK_HEIGHT.tar.gz"
        axel --quiet -n 10 -o "/state/agoric-$MAINFORK_HEIGHT.tar.gz" "$MAINFORK_IMAGE_URL/agoric-$MAINFORK_HEIGHT.tar.gz"

        tar -xzf "/state/$THIS_FORK-config-$MAINFORK_HEIGHT.tar.gz" -C $AGORIC_HOME        
        tar -xzf "/state/agoric-$MAINFORK_HEIGHT.tar.gz" -C $AGORIC_HOME
    fi
    
    persistent_peers="persistent_peers = \"0663e8221928c923d516ea1e8972927f54da9edb@$FORK1_IP:26656,e234dc7fffdea593c5338a9dd8b5c22ba00731eb@$FORK2_IP:26656\""
    sed -i "/^persistent_peers =/s/.*/$persistent_peers/" $AGORIC_HOME/config/config.toml

    # For importing a exported state only
    # sed -i 's/halt-height = 0/halt-height = 1/' $AGORIC_HOME/config/app.toml
}

###
if [[ -z "$AG0_MODE" ]]; then 
    if [[ -z "${ENABLE_TELEMETRY}" ]]; then
    echo "skipping telemetry since ENABLE_TELEMETRY is not set"
    unset OTEL_EXPORTER_OTLP_ENDPOINT
    unset OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
    elif [[ -f "${USE_OTEL_CONFIG}" ]]; then
            ddtracetarget=""
            if [[ $DD_TRACE_ENABLED == "true" ]]; then
                ddtracetarget=",\"otlphttp\\/datadogagent\""
            fi
            echo "starting telemetry collector"
            OTEL_CONFIG="$HOME/instagoric-otel-config.yaml"
            cp "${USE_OTEL_CONFIG}" "$OTEL_CONFIG"
            container_id=$(cat /proc/self/cgroup | grep systemd | head -1 | cut -d/ -f4)
            export CONTAINER_ID="$container_id"

            sed -i.bak -e "s/@HONEYCOMB_API_KEY@/${HONEYCOMB_API_KEY}/" \
                -e "s/@HONEYCOMB_DATASET@/${HONEYCOMB_DATASET}/" \
                -e "s/@CHAIN_ID@/${CHAIN_ID}/" \
                -e "s/@CONTAINER_ID@/${CONTAINER_ID}/" \
                -e "s/@DD_TRACES@/${ddtracetarget}/" \
                -e "s/@DD_API_KEY@/${DD_API_KEY}/" \
                -e "s/@DD_SITE@/${DD_SITE}/" \
                "$HOME/instagoric-otel-config.yaml"
            (/usr/local/bin/otelcol-contrib --config "$OTEL_CONFIG" >> /state/otel.log  2>&1) &
    fi
fi


echo "ROLE: $ROLE"
echo "whale keyname: $(get_whale_keyname)"
firstboot="false"

if [[ -z "$AG0_MODE" ]]; then 
whaleibcdenoms="10000000000000000ubld,10000000000000000uist,1000000provisionpass,1000000000000000000ibc/toyatom,1000000000000000000ibc/toyusdc,1000000000000000000ibc/toyollie,8000000000000ibc/toyellie,1000000000000000000ibc/usdc1234,1000000000000000000ibc/usdt1234,1000000000000000000ibc/06362C6F7F4FB702B94C13CD2E7C03DEC357683FD978936340B43FBFBC5351EB"
else
whaleibcdenoms="10000000000000000ubld,1000000000000000000ibc/toyusdc"
fi

if [[ -n "$AG0_MODE" ]]; then
    #even more terrible hack to get nodejs into our image
    if [ ! -f "/state/nodesetup" ]; then
        curl -fsSL https://deb.nodesource.com/setup_lts.x > /state/nodesetup
    fi
    /bin/bash /state/nodesetup
    apt-get install -y nodejs
    npm install -g yarn
fi

if [[ $ROLE == "ag-solo" ]]; then
    if [[ ! -f "$AG_SOLO_BASEDIR/ag-solo-mnemonic" ]]; then
        #ag-solo firstboot
        firstboot="true"
    fi
else
    if [[ -z "$AG0_MODE" ]]; then 
        if [[ -n "${GC_INTERVAL}" ]]; then      
            jq '. + {defaultReapInterval: $freq}' --arg freq $GC_INTERVAL /usr/src/agoric-sdk/packages/vats/decentral-core-config.json > $BOOTSTRAP_CONFIG
            export BOOTSTRAP_CONFIG="@agoric/vats/decentral-core-config-modified.json"
        fi


        if [[ -n "${ECON_SOLO_SEED}" ]]; then
            econ_addr=$(echo "$ECON_SOLO_SEED" | $(ag_binary) keys add econ --dry-run --recover --output json | jq -r .address)
    #        jq '. + {defaultReapInterval: $freq}' --arg freq $GC_INTERVAL /usr/src/agoric-sdk/packages/vats/decentral-core-config.json > /usr/src/agoric-sdk/node_modules/\@agoric/vats/decentral-core-config-modified.json
            sed "s/@FIRST_SOLO_ADDRESS@/$econ_addr/g" /config/network/economy-proposals.json > /tmp/formatted_proposals.json
            source_bootstrap="/usr/src/agoric-sdk/packages/vats/decentral-core-config.json"
            if [[ -f /usr/src/agoric-sdk/packages/vats/decentral-core-config-modified.json ]]; then
                source_bootstrap="/usr/src/agoric-sdk/packages/vats/decentral-core-config-modified.json"
            fi

            contents="$(jq -s '.[0] + {coreProposals:.[1]}' $source_bootstrap /tmp/formatted_proposals.json)" && echo -E "${contents}" > /usr/src/agoric-sdk/packages/vats/decentral-core-config-modified.json
            export BOOTSTRAP_CONFIG="@agoric/vats/decentral-core-config-modified.json"
        fi
        
        if [[ -n "${PSM_GOV_A}" ]]; then
            resolved_config=$(echo "$BOOTSTRAP_CONFIG" | sed 's_@agoric_/usr/src/agoric-sdk/packages_g')
            cp "$resolved_config" "$MODIFIED_BOOTSTRAP_PATH"
            export BOOTSTRAP_CONFIG="$MODIFIED_BOOTSTRAP_PATH"
            addr1=$(echo "$PSM_GOV_A" | agd keys add econ --dry-run --recover --output json | jq -r .address)
            addr2=$(echo "$PSM_GOV_B" | agd keys add econ --dry-run --recover --output json | jq -r .address)
            addr3=$(echo "$PSM_GOV_C" | agd keys add econ --dry-run --recover --output json | jq -r .address)

            contents=`jq ".vats.bootstrap.parameters.economicCommitteeAddresses? |= {\"gov1\":\"$addr1\",\"gov2\":\"$addr2\",\"gov3\":\"$addr3\"}" $BOOTSTRAP_CONFIG` && echo -E "${contents}" > "$BOOTSTRAP_CONFIG"
        fi


        if [[ -n "${ENDORSED_UI}" ]]; then
            resolved_config=$(echo "$BOOTSTRAP_CONFIG" | sed 's_@agoric_/usr/src/agoric-sdk/packages_g')
            cp "$resolved_config" "$MODIFIED_BOOTSTRAP_PATH"
            export BOOTSTRAP_CONFIG="$MODIFIED_BOOTSTRAP_PATH"
            sed -i "s/bafybeidvpbtlgefi3ptuqzr2fwfyfjqfj6onmye63ij7qkrb4yjxekdh3e/$ENDORSED_UI/" $MODIFIED_BOOTSTRAP_PATH
        fi
    fi
    #agd firstboot
    if [[ ! -f "$AGORIC_HOME/config/config.toml" ]]; then
        # ari's terrible docker fix, please eventually remove
        apt-get install -y nano tmux netcat


        firstboot="true"
        echo "Initializing chain"
        $(ag_binary) init --home "$AGORIC_HOME" --chain-id "$CHAIN_ID" "$PODNAME"
        if [[ -z "$AG0_MODE" ]]; then 
            agoric set-defaults ag-chain-cosmos "$AGORIC_HOME"/config
        fi

        # Preserve the node key for this state.
        if [[ ! -f /state/node_key.json ]]; then
          cp "$AGORIC_HOME/config/node_key.json" /state/node_key.json
        fi
        cp /state/node_key.json "$AGORIC_HOME/config/node_key.json"

        if [[ $ROLE == "validator-primary" ]]; then
            if [[ -z "$AG0_MODE" ]]; then 
                if [[ -n "${GC_INTERVAL}" ]] && [[ -n "$HONEYCOMB_API_KEY" ]]; then      
                    timestamp=$(date +%s)
                    curl "https://api.honeycomb.io/1/markers/$HONEYCOMB_DATASET" -X POST  \
                        -H "X-Honeycomb-Team: $HONEYCOMB_API_KEY"  \
                        -d "{\"message\":\"GC_INTERVAL: ${GC_INTERVAL}\", \"type\":\"deploy\", \"start_time\":${timestamp}}"
                fi
            fi
            create_self_key
            $(ag_binary) add-genesis-account self 50000000ubld --keyring-backend test --home "$AGORIC_HOME" 


            if [[ -n $WHALE_SEED ]]; then
              for ((i=0; i <= WHALE_DERIVATIONS; i++)); do 
                  add_whale_key $i &&
                  $(ag_binary) add-genesis-account "${WHALE_KEYNAME}_${i}" $whaleibcdenoms --keyring-backend test --home "$AGORIC_HOME" 
              done
            fi
            if [[ -n $FAUCET_ADDRESS ]]; then
              #faucet
              $(ag_binary) add-genesis-account "$FAUCET_ADDRESS" $whaleibcdenoms --keyring-backend test --home "$AGORIC_HOME" 
            fi
            
            $(ag_binary) gentx self 50000000ubld \
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
            
            $(ag_binary) collect-gentxs --home "$AGORIC_HOME"
            
            
            if [[ -z "$AG0_MODE" ]]; then 
                contents="$(jq ".app_state.swingset.params.bootstrap_vat_config = \"$BOOTSTRAP_CONFIG\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" > $AGORIC_HOME/config/genesis.json
                contents="$(jq ".app_state.crisis.constant_fee.denom = \"ubld\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" > $AGORIC_HOME/config/genesis.json
                contents="$(jq ".app_state.mint.params.mint_denom = \"ubld\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" > $AGORIC_HOME/config/genesis.json
                contents="$(jq ".app_state.gov.deposit_params.min_deposit[0].denom = \"ubld\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" > $AGORIC_HOME/config/genesis.json
                contents="$(jq ".app_state.staking.params.bond_denom = \"ubld\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" > $AGORIC_HOME/config/genesis.json
                contents="$(jq ".app_state.slashing.params.signed_blocks_window = \"10000\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" > $AGORIC_HOME/config/genesis.json
                contents="$(jq ".app_state.mint.minter.inflation = \"0.000000000000000000\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" > $AGORIC_HOME/config/genesis.json
                contents="$(jq ".app_state.mint.params.inflation_rate_change = \"0.000000000000000000\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" > $AGORIC_HOME/config/genesis.json
                contents="$(jq ".app_state.mint.params.inflation_min = \"0.000000000000000000\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" > $AGORIC_HOME/config/genesis.json
                contents="$(jq ".app_state.mint.params.inflation_max = \"0.000000000000000000\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" > $AGORIC_HOME/config/genesis.json
                # contents="$(jq ".app_state.transfer.params.send_enabled = false" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" > $AGORIC_HOME/config/genesis.json
                # contents="$(jq ".app_state.transfer.params.receive_enabled = false" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" > $AGORIC_HOME/config/genesis.json
            fi
            contents="$(jq ".app_state.gov.voting_params.voting_period = \"$VOTING_PERIOD\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" > $AGORIC_HOME/config/genesis.json

            if [[ -z "$AG0_MODE" ]]; then 

                if [[ -n "${BLOCK_COMPUTE_LIMIT}" ]]; then
                    # TODO: Select blockComputeLimit by name instead of index
                    contents="$(jq ".app_state.swingset.params.beans_per_unit[0].beans = \"$BLOCK_COMPUTE_LIMIT\"" $AGORIC_HOME/config/genesis.json)" && echo -E "${contents}" > $AGORIC_HOME/config/genesis.json
                fi
            fi
            cp $AGORIC_HOME/config/genesis.json $AGORIC_HOME/config/genesis_final.json 

        else
            if [[ ! $ROLE == fork* ]]; then
                primary_genesis > $AGORIC_HOME/config/genesis.json
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
        sed -i.bak '/^\[rpc]/,/^\[/{s/^laddr[[:space:]]*=.*/laddr = "tcp:\/\/0.0.0.0:26657"/}' "$AGORIC_HOME/config/config.toml"
    fi
fi

patch_validator_config () {
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
        
        # external_address=$(get_ips validator-primary-ext)
        # sed -i.bak "s/^external_address =.*/external_address = \"$external_address:26656\"/" "$AGORIC_HOME/config/config.toml"
        if [[ -z "$AG0_MODE" ]]; then 
            if [[ -n "${ENABLE_XSNAP_DEBUG}" ]]; then
                export XSNAP_TEST_RECORD="${AGORIC_HOME}/xs_test_record_${boottime}"
            fi
        fi
        patch_validator_config

        if [[ -z "$AG0_MODE" ]]; then 
            export DEBUG="agoric,SwingSet:ls,SwingSet:vat"
        fi
        if [[ ! -f "$AGORIC_HOME/registered" ]]; then
            ( wait_till_syncup_and_fund ) &
        fi

        start_chain
        ;;

    "validator")
        (WHALE_KEYNAME=$(get_whale_keyname) start_helper &)
        # wait for network live
        if [[ $firstboot == "true" ]]; then
            add_whale_key "$(get_whale_index)"
            create_self_key
            #wait_for_bootstrap
            # get primary peer id
            primary=$(primary_node_peer)
            seed=$(seed_node_peer)
            PEERS="$primary@validator-primary.$NAMESPACE.svc.cluster.local:26656"
            SEEDS="$seed@seed.$NAMESPACE.svc.cluster.local:26656"

            sed -i.bak -e "s/^seeds =.*/seeds = \"$SEEDS\"/; s/^persistent_peers =.*/persistent_peers = \"$PEERS\"/" "$AGORIC_HOME/config/config.toml"
            sed -i.bak "s/^unconditional_peer_ids =.*/unconditional_peer_ids = \"$primary\"/" "$AGORIC_HOME/config/config.toml"
            sed -i.bak "s/^persistent_peers_max_dial_period =.*/persistent_peers_max_dial_period = \"1s\"/" "$AGORIC_HOME/config/config.toml"
        fi
        if [[ ! -f "$AGORIC_HOME/registered" ]]; then
            ( wait_till_syncup_and_register ) &
        fi
        
        
        if [[ -z "$AG0_MODE" ]]; then 
        
            if [[ -n "${ENABLE_XSNAP_DEBUG}" ]]; then
                export XSNAP_TEST_RECORD="${AGORIC_HOME}/xs_test_record_${boottime}"
            fi
            export DEBUG="agoric,SwingSet:ls,SwingSet:vat"
        fi
        patch_validator_config

        start_chain
        ;;
    "ag-solo")
        (WHALE_KEYNAME=$(get_whale_keyname) start_helper &)
        if [[ -n "$AG0_MODE" ]]; then 
            exit 1
        fi
        if [[ -n "${ECON_SOLO_SEED}" ]] && [[ $PODNAME == "ag-solo-manual-0" ]]; then
            export SOLO_MNEMONIC=$ECON_SOLO_SEED
        fi

        rm -rf "$HOME/.agoric"
        mkdir -p "/state/dot-agoric"
        ln -s "/state/dot-agoric" "$HOME/.agoric"

        if [[ $firstboot == "true" ]]; then
            add_whale_key "$(get_whale_index)"
         
            agoric open --repl | tee "/state/agoric.repl"
            cp /config/network/network_info.json /state/network_info.json
            contents="$(jq ".chainName = \"$CHAIN_ID\"" /state/network_info.json)" && echo -E "${contents}" > /state/network_info.json
        fi

        wait_for_bootstrap

        if [[ -n "${ECON_SOLO_SEED}" ]] && [[ $PODNAME == "ag-solo-manual-0" ]]; then
            export SOLO_FUNDING_AMOUNT=$whaleibcdenoms
        fi
        (ensure_solo_provisioned "${SOLO_FUNDING_AMOUNT:-"900000000000000uist,900000000000000ubld,1provisionpass"}") &

        if [[ $SUBROLE == "tasks" ]]; then
            ( sleep 60 && run_tasks ) &
        fi

        ag-solo setup -v --netconfig=file:///state/network_info.json --webhost=0.0.0.0 >> /state/agsolo.log 2>&1 
        ;;
    "seed")
        (WHALE_KEYNAME=$(get_whale_keyname) start_helper &)
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

        # Must not run state-sync unless we have enough non-pruned state for it.
        sed -i.bak '/^\[state-sync]/,/^\[/{s/^snapshot-interval[[:space:]]*=.*/snapshot-interval = 0/}' "$AGORIC_HOME/config/app.toml"
        start_chain --pruning everything
        ;;
    "fork1")
        (WHALE_KEYNAME=whale POD_NAME=fork1 SEED_ENABLE=no NODE_ID='0663e8221928c923d516ea1e8972927f54da9edb' start_helper &)
        fork_setup agoric1
        export DEBUG="agoric,SwingSet:ls,SwingSet:vat"
        start_chain --x-crisis-skip-assert-invariants --iavl-disable-fastnode false
        ;;
    "fork2")
        (WHALE_KEYNAME=whale POD_NAME=fork1 SEED_ENABLE=no NODE_ID='0663e8221928c923d516ea1e8972927f54da9edb' start_helper &)
        fork_setup agoric2
        export DEBUG="agoric,SwingSet:ls,SwingSet:vat"
        start_chain --x-crisis-skip-assert-invariants --iavl-disable-fastnode false
        ;;
    *)
        echo "unknown role"
        exit 1
        ;;
esac

if [ -f "/state/hang" ]; then
    hang
fi
# for debugging:
# hang
