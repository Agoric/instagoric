#!/bin/bash

export API_ENDPOINT="https://kubernetes.default.svc"
export AUTO_APPROVE_PROPOSAL=${AUTO_APPROVE_PROPOSAL:-"false"}
# shellcheck disable=SC2155
export BOOT_TIME="$(date '+%s')"
export CA_PATH=${CA_PATH:-"/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"}
export CHAIN_ID=${CHAIN_ID:-instagoric-1}
export ENDPOINT="http://validator.$NAMESPACE.svc.cluster.local"
export MAINFORK_HEIGHT=17231232
export MAINFORK_IMAGE_URL="https://storage.googleapis.com/agoric-snapshots-public/mainfork-snapshots"
export MAINNET_ADDRBOOK_URL="https://snapshots.polkachu.com/addrbook/agoric/addrbook.json"
export MAINNET_SNAPSHOT="agoric_15131589.tar.lz4"
export MAINNET_SNAPSHOT_URL="https://snapshots.polkachu.com/snapshots/agoric"
export NAMESPACE_PATH="/var/run/secrets/kubernetes.io/serviceaccount/namespace"
export OTEL_VERSION=0.96.0
export PRIMARY_ENDPOINT="http://validator-primary.$NAMESPACE.svc.cluster.local"
export PRIMARY_NOD_PEER_ID="fb86a0993c694c981a28fa1ebd1fd692f345348b"
export PRIVATE_APP_PORT="8002"
export RPC_ENDPOINT="http://rpcnodes.$NAMESPACE.svc.cluster.local"
export SDK_ROOT_PATH=${SDK_ROOT_PATH:-"/usr/src/agoric-sdk"}
export SEED_NOD_PEER_ID="0f04c4610b7511a64b8644944b907416db568590"
export TMPDIR="/state/tmp"
export TOKEN_PATH="/var/run/secrets/kubernetes.io/serviceaccount/token"
export VOTING_PERIOD=${VOTING_PERIOD:-18h}
export WHALE_DERIVATIONS=${WHALE_DERIVATIONS:-100}
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
