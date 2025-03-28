#! /bin/sh

set -o errexit -o nounset

COMMIT_HASH="4d2d093560c52e08458f97f451dc1f0690e00094"
NETDOMAIN="${NETDOMAIN:-".agoric.net"}"
PING_PUB_REPOSITORY_LINK="https://github.com/ping-pub/explorer.git"
PING_PUB_SOURCE="/workspace"
SERVER_PORT="8080"

build() {
  yarn --cwd "$PING_PUB_SOURCE"
  yarn --cwd "$PING_PUB_SOURCE" build
}

copy_logos() {
  mkdir --parents "$PING_PUB_SOURCE/dist/logos"
  cp "/entrypoint/agoric.png" "$PING_PUB_SOURCE/dist/logos/agoric.png"
  cp "/entrypoint/agoric-bld.svg" "$PING_PUB_SOURCE/dist/logos/agoric-bld.svg"
}

set_chain_data() {
  rm --force $PING_PUB_SOURCE/chains/mainnet/*.json $PING_PUB_SOURCE/chains/testnet/*.json

  jq ".api[] = \"/api\" | .apiDirect = [\"https://$NETNAME.api$NETDOMAIN\"] | .rpc[] = \"/rpc\" | .rpcDirect = [\"https://$NETNAME.rpc$NETDOMAIN\"]" \
    --raw-output \
    <"/entrypoint/agoric.json" >"$PING_PUB_SOURCE/chains/mainnet/agoric.json"
}

setup() {
  apt-get update
  apt-get install git jq --yes
  corepack enable
}

setup_repository() {
  git clone "$PING_PUB_REPOSITORY_LINK" "$PING_PUB_SOURCE"
  git -C "$PING_PUB_SOURCE" checkout "$COMMIT_HASH"
  patch --directory "$PING_PUB_SOURCE" --input "/entrypoint/config.patch" --strip "1"
  sed "$PING_PUB_SOURCE/vite.config.ts" \
    --expression "s|\$RPCNODES_SERVICE_HOST|$RPCNODES_SERVICE_HOST|" \
    --expression "s|\$RPCNODES_SERVICE_PORT_API|$RPCNODES_SERVICE_PORT_API|" \
    --expression "s|\$RPCNODES_SERVICE_PORT_RPC|$RPCNODES_SERVICE_PORT_RPC|" \
    --in-place
}

start_server() {
  yarn \
    --cwd "$PING_PUB_SOURCE" \
    preview \
    --host \
    --port "$SERVER_PORT"
}

setup
setup_repository
set_chain_data
build
copy_logos
start_server
