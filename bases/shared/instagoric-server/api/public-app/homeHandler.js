// @ts-check
import {
  NETDOMAIN,
  NETNAME,
  namespace,
  revision,
  DOCKERIMAGE,
  DOCKERTAG,
  podname,
  FAKE,
  chainId,
} from '../../constants.js';
import { getDockerImage } from '../../utils.js';
import process from 'process';
export async function homeRoute(req, res) {
  let CLUSTER_NAME;
  let dockerImage = await getDockerImage(namespace, podname, FAKE);
  const domain = NETDOMAIN;
  const netname = NETNAME;
  const gcloudLoggingDatasource = 'P470A85C5170C7A1D';
  const logsQuery = {
    '62l': {
      datasource: gcloudLoggingDatasource,
      queries: [
        {
          queryText: `resource.labels.container_name=\"log-slog\" resource.labels.namespace_name=\"${namespace}\" resource.labels.cluster_name=\"${CLUSTER_NAME}\"`,
        },
      ],
    },
  };
  const logsUrl = `https://monitor${domain}/explore?schemaVersion=1&panes=${encodeURI(
    JSON.stringify(logsQuery),
  )}&orgId=1`;
  const dashboardUrl = `https://monitor${domain}/d/cdzujrg5sxvy8f/agoric-chain-metrics?var-cluster=${CLUSTER_NAME}&var-namespace=${namespace}&var-chain_id=${chainId}&orgId=1`;
  res.send(`
  <html><head><title>Instagoric</title></head><body><pre>
  ██╗███╗   ██╗███████╗████████╗ █████╗  ██████╗  ██████╗ ██████╗ ██╗ ██████╗
  ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██╔════╝ ██╔═══██╗██╔══██╗██║██╔════╝
  ██║██╔██╗ ██║███████╗   ██║   ███████║██║  ███╗██║   ██║██████╔╝██║██║
  ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║   ██║██║   ██║██╔══██╗██║██║
  ██║██║ ╚████║███████║   ██║   ██║  ██║╚██████╔╝╚██████╔╝██║  ██║██║╚██████╗
  ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝ ╚═════╝
  
  Chain: ${chainId}${
    process.env.NETPURPOSE !== undefined
      ? `\nPurpose: ${process.env.NETPURPOSE}`
      : ''
  }
  Revision: ${revision}
  Docker Image: ${DOCKERIMAGE || dockerImage.split(':')[0]}:${
    DOCKERTAG || dockerImage.split(':')[1]
  }
  Revision Link: <a href="https://github.com/Agoric/agoric-sdk/tree/${revision}">https://github.com/Agoric/agoric-sdk/tree/${revision}</a>
  Network Config: <a href="https://${netname}${domain}/network-config">https://${netname}${domain}/network-config</a>
  Docker Compose: <a href="https://${netname}${domain}/docker-compose.yml">https://${netname}${domain}/docker-compose.yml</a>
  RPC: <a href="https://${netname}.rpc${domain}">https://${netname}.rpc${domain}</a>
  gRPC: <a href="https://${netname}.grpc${domain}">https://${netname}.grpc${domain}</a>
  API: <a href="https://${netname}.api${domain}">https://${netname}.api${domain}</a>
  Explorer: <a href="https://${netname}.explorer${domain}">https://${netname}.explorer${domain}</a>
  Faucet: <a href="https://${netname}.faucet${domain}">https://${netname}.faucet${domain}</a>
  Logs: <a href=${logsUrl}>Click Here</a>
  Monitoring Dashboard: <a href=${dashboardUrl}>Click Here</a>
  VStorage: <a href="https://vstorage.agoric.net/?path=&endpoint=https://${
    netname === 'followmain' ? 'main-a' : netname
  }.rpc.agoric.net">https://vstorage.agoric.net/?endpoint=https://${
    netname === 'followmain' ? 'main-a' : netname
  }.rpc.agoric.net</a>
  
  UIs:
  Main-branch Wallet: <a href="https://main.wallet-app.pages.dev/wallet/">https://main.wallet-app.pages.dev/wallet/</a>
  Main-branch Vaults: <a href="https://dapp-inter-test.pages.dev/?network=${netname}">https://dapp-inter-test.pages.dev/?network=${netname}</a>
  
  ----
  See more at <a href="https://agoric.com">https://agoric.com</a>
  </pre></body></html>
    `);
}
