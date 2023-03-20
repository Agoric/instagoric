#!/bin/sh
cd /workspace
cp ./src/chains/mainnet/agoric.json /tmp/agoric.json
cp ./src/chains/testnet/agoric.json /tmp/agoric_test.json
rm ./src/chains/mainnet/*.json
rm ./src/chains/testnet/*.json
mv /tmp/agoric.json ./src/chains/mainnet/agoric.json
mv /tmp/agoric_test.json ./src/chains/testnet/agoric.json

NETDOMAIN=${NETDOMAIN:-.agoric.net}
cat ./src/chains/mainnet/agoric.json | jq ".api=[\"https:\/\/${NETNAME}.api${NETDOMAIN}\"] | .rpc=[\"https:\/\/${NETNAME}.rpc${NETDOMAIN}\"]" > /tmp/1.json
cp /tmp/1.json ./src/chains/mainnet/agoric.json

cat vue.config.js | sed "s/devServer: {/devServer: {allowedHosts: 'all',/g" > /tmp/v.js
mv /tmp/v.js vue.config.js

yarn && ./node_modules/.bin/vue-cli-service serve --mode=production --port=8080 
