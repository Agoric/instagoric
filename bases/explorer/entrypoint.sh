#! /bin/sh

set -o errexit -o nounset

COMMIT_HASH="4d2d093560c52e08458f97f451dc1f0690e00094"
NETDOMAIN=${NETDOMAIN:-".agoric.net"}
PING_PUB_REPOSITORY_LINK="https://github.com/ping-pub/explorer.git"
PING_PUB_SOURCE="/workspace"

apt-get update
apt-get install git jq --yes
corepack enable

git clone "$PING_PUB_REPOSITORY_LINK" "$PING_PUB_SOURCE"
git -C "$PING_PUB_SOURCE" checkout "$COMMIT_HASH"

rm --force $PING_PUB_SOURCE/chains/mainnet/*.json $PING_PUB_SOURCE/chains/testnet/*.json

jq ".api[] = \"https://$NETNAME.api$NETDOMAIN\" | .rpc[] = \"https://$NETNAME.rpc$NETDOMAIN\"" \
  --raw-output \
  <"/entrypoint/agoric.json" >"$PING_PUB_SOURCE/chains/mainnet/agoric.json"

yarn --cwd "$PING_PUB_SOURCE"
yarn --cwd "$PING_PUB_SOURCE" build

mkdir --parents "$PING_PUB_SOURCE/dist/logos"
cp "/entrypoint/agoric.png" "$PING_PUB_SOURCE/dist/logos/agoric.png"
cp "/entrypoint/agoric-bld.svg" "$PING_PUB_SOURCE/dist/logos/agoric-bld.svg"

yarn --cwd "$PING_PUB_SOURCE" preview --host --port 8080
