#!/bin/bash

export API_ENDPOINT="https://kubernetes.default.svc"
export AUTO_APPROVE_PROPOSAL=${AUTO_APPROVE_PROPOSAL:-"false"}
# shellcheck disable=SC2155
export BOOT_TIME="$(date '+%s')"
export BOOTSTRAP_CONFIG_PATCH_FILE="/config/instagoric-release/bootstrap-config.patch"
export CA_PATH=${CA_PATH:-"/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"}
export CHAIN_ID=${CHAIN_ID:-instagoric-1}
export ENDPOINT="http://validator.$NAMESPACE.svc.cluster.local"
export HANG_FILE_PATH="/state/hang"
export MAINFORK_HEIGHT=17231232
export MAINFORK_IMAGE_URL="https://storage.googleapis.com/agoric-snapshots-public/mainfork-snapshots"
export MAINNET_ADDRBOOK_URL="https://snapshots.polkachu.com/addrbook/agoric/addrbook.json"
export MAINNET_SNAPSHOT="agoric_15131589.tar.lz4"
export MAINNET_SNAPSHOT_URL="https://snapshots.polkachu.com/snapshots/agoric"
export NAMESPACE_PATH="/var/run/secrets/kubernetes.io/serviceaccount/namespace"
export OTEL_VERSION=0.109.0
export P2P_PORT="26656"
export PRIMARY_ENDPOINT="http://validator-primary.$NAMESPACE.svc.cluster.local"
export PRIMARY_NOD_PEER_ID="fb86a0993c694c981a28fa1ebd1fd692f345348b"
export PRIMARY_VALIDATOR_SERVICE_NAME="validator-primary-ext"
export PRIVATE_APP_PORT="8002"
export PROVISIONING_ADDRESS="agoric1megzytg65cyrgzs6fvzxgrcqvwwl7ugpt62346"
export RPC_ENDPOINT="http://rpcnodes.$NAMESPACE.svc.cluster.local"
export RPC_PORT="26657"
export SDK_ROOT_PATH=${SDK_ROOT_PATH:-"/usr/src/agoric-sdk"}
export SEED_NOD_PEER_ID="0f04c4610b7511a64b8644944b907416db568590"
export SEED_SERVICE_NAME="seed-ext"
export TMPDIR="/state/tmp"
export TOKEN_PATH="/var/run/secrets/kubernetes.io/serviceaccount/token"
export VOTING_PERIOD=${VOTING_PERIOD:-18h}
export WHALE_DERIVATIONS=${WHALE_DERIVATIONS:-100}
export WHALE_IBC_DENOMS="10000000000000000ubld,10000000000000000uist,1000000provisionpass,1000000000000000000ibc/toyatom,1000000000000000000ibc/toyusdc,1000000000000000000ibc/toyollie,8000000000000ibc/toyellie,1000000000000000000ibc/usdc1234,1000000000000000000ibc/usdt1234,1000000000000000000ibc/06362C6F7F4FB702B94C13CD2E7C03DEC357683FD978936340B43FBFBC5351EB"
export WHALE_KEYNAME="whale"

export AG_SOLO_BASEDIR="/state/$CHAIN_ID-solo"
export AGORIC_HOME="/state/$CHAIN_ID"
export APP_LOG_FILE="/state/app_${BOOT_TIME}.log"
export BOOTSTRAP_CONFIG=${BOOTSTRAP_CONFIG:-"@agoric/vats/decentral-demo-config.json"}
export CONTEXTUAL_SLOGFILE="/state/contextual_slogs_${BOOT_TIME}.json"
export MODIFIED_BOOTSTRAP_PATH="$SDK_ROOT_PATH/packages/vats/modified-bootstrap.json"
export OTEL_LOG_FILE="/state/otel_${BOOT_TIME}.log"
export SERVER_LOG_FILE="/state/server_${BOOT_TIME}.log"
export SLOGFILE="/state/slogfile_${BOOT_TIME}.json"
# shellcheck disable=SC2155
export TOKEN=$(cat $TOKEN_PATH)

export SWINGSTORE="$AGORIC_HOME/data/agoric/swingstore.sqlite"
