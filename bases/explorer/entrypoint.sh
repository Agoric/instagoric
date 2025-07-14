#! /bin/sh

set -o errexit -o nounset

NETDOMAIN="${NETDOMAIN:-".agoric.net"}"
PING_PUB_REPOSITORY_LINK="https://github.com/agoric-labs/ping-pub-explorer.git"
PING_PUB_SOURCE="/workspace"
SERVER_PORT="8080"

build() {
  yarn --cwd "$PING_PUB_SOURCE"
  yarn --cwd "$PING_PUB_SOURCE" build
}

set_chain_data() {
  file_path="$PING_PUB_SOURCE/chains/mainnet/agoric.json"
  chain_data=$(
    jq ".api[] = \"/api\" | .apiDirect = [\"https://$NETNAME.api$NETDOMAIN\"] | .rpc[] = \"/rpc\" | .rpcDirect = [\"https://$NETNAME.rpc$NETDOMAIN\"]" \
      --raw-output \
      <"$file_path"
  )
  echo "$chain_data" >"$file_path"
}

setup() {
  apt-get update
  apt-get install git jq --yes
}

setup
git clone "$PING_PUB_REPOSITORY_LINK" "$PING_PUB_SOURCE" --branch "master"
set_chain_data
build
PORT="$SERVER_PORT" yarn --cwd "$PING_PUB_SOURCE" preview
