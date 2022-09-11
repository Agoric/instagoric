#!/bin/sh
cd /workspace
cp ./src/chains/mainnet/agoric.json /tmp/agoric.json
cp ./src/chains/testnet/agoric.json /tmp/agoric_test.json
rm ./src/chains/mainnet/*.json
rm ./src/chains/testnet/*.json
mv /tmp/agoric.json ./src/chains/mainnet/agoric.json
mv /tmp/agoric_test.json ./src/chains/testnet/agoric.json

NETDOMAIN=${NETDOMAIN:-.agoric.net}
cat ./src/chains/mainnet/agoric.json | sed "s/^.*\"api\": .*/    \"api\": [\"https:\/\/${NETNAME}.api${NETDOMAIN}\"],/g" > /tmp/1.json
cat /tmp/1.json | sed "s/^.*\"rpc\": .*/    \"rpc\": [\"https:\/\/${NETNAME}.rpc${NETDOMAIN}:443\"],/g" > ./src/chains/mainnet/agoric.json

cat vue.config.js | sed "s/devServer: {/devServer: {allowedHosts: 'all',/g" > /tmp/v.js
mv /tmp/v.js vue.config.js

yarn && ./node_modules/.bin/vue-cli-service serve --mode=production --port=8080 
