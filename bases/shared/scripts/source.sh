#!/bin/bash

export API_ENDPOINT=https://kubernetes.default.svc
export AUTO_APPROVE_PROPOSAL=${AUTO_APPROVE_PROPOSAL:-"false"}
# shellcheck disable=SC2155
export boottime="$(date '+%s')"
export CA_PATH=${CA_PATH:-"/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"}
export CHAIN_ID=${CHAIN_ID:-instagoric-1}
export DD_AGENT_HOST=datadog.datadog.svc.cluster.local
export DD_SERVICE="agd"
export ENDPOINT="http://validator.$NAMESPACE.svc.cluster.local"
export MAINFORK_HEIGHT=16227216
export MAINFORK_IMAGE_URL="https://storage.googleapis.com/agoric-snapshots-public/mainfork-snapshots"
export MAINNET_ADDRBOOK_URL="https://snapshots.polkachu.com/addrbook/agoric/addrbook.json"
export MAINNET_SNAPSHOT="agoric_14538863.tar.lz4"
export MAINNET_SNAPSHOT_URL="https://snapshots.polkachu.com/snapshots/agoric"
export MODIFIED_BOOTSTRAP_PATH="/usr/src/agoric-sdk/packages/vats/modified-bootstrap.json"
export NAMESPACE_PATH=/var/run/secrets/kubernetes.io/serviceaccount/namespace
export PRIMARY_ENDPOINT="http://validator-primary.$NAMESPACE.svc.cluster.local"
export RPC_ENDPOINT="http://rpcnodes.$NAMESPACE.svc.cluster.local"
export SDK_ROOT_PATH=${SDK_ROOT_PATH:-"/usr/src/agoric-sdk"}
export TMPDIR=/state/tmp
export TOKEN_PATH=/var/run/secrets/kubernetes.io/serviceaccount/token
export VOTING_PERIOD=${VOTING_PERIOD:-18h}
export WHALE_DERIVATIONS=${WHALE_DERIVATIONS:-100}
export WHALE_KEYNAME="whale"

export AG_SOLO_BASEDIR="/state/$CHAIN_ID-solo"
export AGORIC_HOME="/state/$CHAIN_ID"
export BOOTSTRAP_CONFIG=${BOOTSTRAP_CONFIG:-"@agoric/vats/decentral-demo-config.json"}
export DD_ENV=$CHAIN_ID
# shellcheck disable=SC2155
export DD_VERSION=$(tr '\n' ' ' < "$SDK_ROOT_PATH/packages/solo/public/git-revision.txt" )
# shellcheck disable=SC2155
export NAMESPACE=$(cat $NAMESPACE_PATH)
export SLOGFILE="/state/slogfile_${boottime}.json"
# shellcheck disable=SC2155
export TOKEN=$(cat $TOKEN_PATH)

export SWINGSTORE="$AGORIC_HOME/data/agoric/swingstore.sqlite"