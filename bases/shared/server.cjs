var fs = require('fs');
var path = require('path');

const https = require('https');
const spawn = require('child_process').spawn;

let dockerImage;

const namespace = (process.env.NAMESPACE !== undefined) ? process.env.NAMESPACE : fs.readFileSync("/var/run/secrets/kubernetes.io/serviceaccount/namespace", {encoding:'utf8', flag:'r'});

// function returns a Promise
function getPromise(url) {
	return new Promise((resolve, reject) => {
    let token = fs.readFileSync("/var/run/secrets/kubernetes.io/serviceaccount/token", {encoding:'utf8', flag:'r'});

    const options = {
      rejectUnauthorized: false,
      keepAlive: false, 
      headers: {
        'Accept': 'application/json',
        'Authorization': "Bearer " + token
      }
    };
    
    https.get(url, options, (response) => {
			let chunks_of_data = [];

			response.on('data', (fragments) => {
				chunks_of_data.push(fragments);
			});

			response.on('end', () => {
				let response_body = Buffer.concat(chunks_of_data);
				resolve(response_body.toString());
			});

			response.on('error', (error) => {
				reject(error);
			});
		});
	});
}

async function makeSynchronousRequest(url) {
	try {
		let http_promise = getPromise(url);
		let response_body = await http_promise;
		return response_body;
	}
	catch(error) {
		console.log(error);
	}
}

async function getNodeId(node){
  let data = await makeSynchronousRequest(`http://${node}.${namespace}.svc.cluster.local:26657/status`);
  let parsed = JSON.parse(data);
  return "asdf";
}


async function getServices(){
  if (process.env.FAKE !== undefined) {
    const map1 = new Map();
    map1.set("validator-primary-ext", "1.1.1.1");
    map1.set("seed-ext", "1.1.1.2");
    return map1;
  }
  let data = await makeSynchronousRequest(`https://kubernetes.default.svc/api/v1/namespaces/${namespace}/services/`);
  let parsed = JSON.parse(data);
  const map1 = new Map();
  for (const item of parsed.items) {
    if ('loadBalancer' in item.status && 'ingress' in item.status.loadBalancer && item.status.loadBalancer.ingress.length > 0){
      map1.set(item.metadata.name,item.status.loadBalancer.ingress[0].ip);
    }
  }
  return map1;
}

const getServiceData = () => {
  return getServices()
    .then((result) => result);
}

const getNetworkConfig = () => {
  return getServices().then((svc) => {
    if (process.env.FAKE !== undefined) {
      file = "./resources/network_info.json";
    } else {
      file = "/config/network/network_info.json";
    }
    buf = fs.readFileSync(file, {encoding:'utf8', flag:'r'});
    var ap = JSON.parse(buf);
    ap.chainName = process.env.CHAIN_ID;
    ap.gci = "https://" + ((process.env.NETNAME !== undefined) ? process.env.NETNAME : "devnet") + ".rpc" +  ((process.env.NETDOMAIN !== undefined) ? process.env.NETDOMAIN : ".agoric.net")+ ":443/genesis";
    ap.peers[0] = ap.peers[0].replace("validator-primary.instagoric.svc.cluster.local", (svc.get('validator-primary-ext') || "validator-primary.instagoric.svc.cluster.local"));
    ap.rpcAddrs = ["https://" + ((process.env.NETNAME !== undefined) ? process.env.NETNAME : "devnet") + ".rpc" +  ((process.env.NETDOMAIN !== undefined) ? process.env.NETDOMAIN : ".agoric.net")+ ":443"];
    ap.seeds[0] = ap.seeds[0].replace("seed.instagoric.svc.cluster.local", (svc.get('seed-ext') || "seed.instagoric.svc.cluster.local"));
    buf = JSON.stringify(ap);
    return buf;
  })
}
class DataCache {
  constructor(fetchFunction, minutesToLive = 10) {
    this.millisecondsToLive = minutesToLive * 60 * 1000;
    this.fetchFunction = fetchFunction;
    this.cache = null;
    this.getData = this.getData.bind(this);
    this.resetCache = this.resetCache.bind(this);
    this.isCacheExpired = this.isCacheExpired.bind(this);
    this.fetchDate = new Date(0);
  }
  isCacheExpired() {
    return (this.fetchDate.getTime() + this.millisecondsToLive) < new Date().getTime();
  }
  getData() {
    if (!this.cache || this.isCacheExpired()) {
      console.log("fetch");
      return this.fetchFunction()
        .then((data) => {
        this.cache = data;
        this.fetchDate = new Date();
        return data;
      });
    } else {
      console.log("cache hit");

      return Promise.resolve(this.cache);
    }
  }
  resetCache() {
   this.fetchDate = new Date(0);
  }
}
const ipsCache = new DataCache(getServiceData, 0.1);
const networkConfig = new DataCache(getNetworkConfig, 0.5);

const express = require('express')
const publicapp = express()
const privateapp = express()
const faucetapp = express()
const publicport = 8001
const privateport = 8002
const faucetport = 8003
const logReq = function(req, res, next) {
  let time = Date.now();
  res.on('finish', function() {
    console.log(JSON.stringify({time: time, dur: Date.now()-time, method: req.method, forwarded: req.get("X-Forwarded-For"), ip: req.ip, url: req.originalUrl, status: this.statusCode}));
  })
  next();
};

publicapp.use(logReq);
privateapp.use(logReq);
faucetapp.use(logReq);

publicapp.get('/', (req, res) => {
  const domain=(process.env.NETDOMAIN || ".agoric.net");
  const netname=(process.env.NETNAME || "devnet");
  res.send(`
<html><head><title>Instagoric</title></head><body><pre>
██╗███╗   ██╗███████╗████████╗ █████╗  ██████╗  ██████╗ ██████╗ ██╗ ██████╗
██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██╔════╝ ██╔═══██╗██╔══██╗██║██╔════╝
██║██╔██╗ ██║███████╗   ██║   ███████║██║  ███╗██║   ██║██████╔╝██║██║     
██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║   ██║██║   ██║██╔══██╗██║██║     
██║██║ ╚████║███████║   ██║   ██║  ██║╚██████╔╝╚██████╔╝██║  ██║██║╚██████╗
╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝ ╚═════╝

Chain: ${process.env.CHAIN_ID || "unknown"}
Network Config: <a href="https://${netname}${domain}/network-config">https://${netname}${domain}/network-config</a>
Docker Compose: <a href="https://${netname}${domain}/docker-compose.yml">https://${netname}${domain}/docker-compose.yml</a>
RPC: <a href="https://${netname}.rpc${domain}">https://${netname}.rpc${domain}</a>
gRPC: <a href="https://${netname}.grpc${domain}">https://${netname}.grpc${domain}</a>
API: <a href="https://${netname}.api${domain}">https://${netname}.api${domain}</a>
Explorer: <a href="https://${netname}.explorer${domain}">https://${netname}.explorer${domain}</a>
Faucet: <a href="https://${netname}.faucet${domain}">https://${netname}.faucet${domain}</a>

----
See more at <a href="https://agoric.com">https://agoric.com</a>
</pre></body></html>                                                     
  `)
});

publicapp.get('/network-config', (req, res) => {
  res.setHeader('Content-type', 'text/plain;charset=UTF-8');
  res.setHeader('Access-Control-Allow-Origin', '*');
  networkConfig.getData()
    .then((result) => {
      res.send(result);
    });
});

const docker_compose_yml = (dockertag, netname, netdomain=".agoric.net") => `version: "2.2"
services:
  ag-solo:
    image: agoric/agoric-sdk:\${SDK_TAG:-${dockertag}}
    ports:
      - "\${HOST_PORT:-8000}:\${PORT:-8000}"
    volumes:
      - "ag-solo-state:/state"
      - "\$HOME/.agoric:/root/.agoric"
    environment:
      - "AG_SOLO_BASEDIR=/state/\${SOLO_HOME:-${dockertag}}"
    entrypoint: ag-solo
    command:
      - setup
      - --webhost=0.0.0.0
      - --webport=\${PORT:-8000}
      - --netconfig=\${NETCONFIG_URL:-https://${netname}${netdomain}/network-config}
volumes:
  ag-solo-state:
`;

publicapp.get('/docker-compose.yml', (req, res) => {
  res.setHeader('Content-disposition', 'attachment; filename=docker-compose.yml');
  res.setHeader('Content-type', 'text/x-yaml;charset=UTF-8');
  res.send(docker_compose_yml(process.env.DOCKERTAG || dockerImage.split(":")[1], process.env.NETNAME || "devnet", process.env.NETDOMAIN || ".agoric.net"));
});


privateapp.get('/', (req, res) => {
  res.send('welcome to instagoric');
});

privateapp.get('/ips', (req, res) => {
  ipsCache.getData()
   .then((result) => {
    if (result.size > 0) {
      res.send(JSON.stringify({status: 1, ips: Object.fromEntries(result)}));
    } else {
      res.status(500).send(JSON.stringify({status: 0, ips: {}}));
      ipsCache.resetCache();
    }
  });
});

privateapp.get('/genesis.json', (req, res) => {
  try {
    file = `/state/${process.env.CHAIN_ID}/config/genesis_final.json`;
    if (fs.existsSync(file)) {
      buf = fs.readFileSync(file, {encoding:'utf8', flag:'r'});
      res.send(buf);
      return
    }
  } catch(err) {
    console.error(err);
  }
  res.status(500).send("error");
});

privateapp.get('/repl', (req, res) => {
  ipsCache.getData()
  .then((svc) => {
   if (svc.length > 0) {
      file = "/state/agoric.repl";
      buf = fs.readFileSync(file, {encoding:'utf8', flag:'r'});
      buf = buf.replace("127.0.0.1", svc.get('ag-solo-manual-ext') || "127.0.0.1");
      res.send(buf);
   } else {
     res.status(500).send("error");
     ipsCache.resetCache();
   }
 });
});

const addressToRequest = new Map();
let requestQueueAdded;
let requestQueueIsNonempty = new Promise(resolve => requestQueueAdded = resolve);
const requestQueue = [];
const faucetRequests = {
  [Symbol.asyncIterator]: () => ({
    next: async () => {
      await requestQueueIsNonempty;
      const request = requestQueue.shift();
      if (!requestQueue.length) {
        requestQueueIsNonempty = new Promise(resolve => requestQueueAdded = resolve);
      }
      return {done: false, value: request}
    }
  }),
};
const addRequest = (address, request) => {
  if (addressToRequest.has(address)) {
    request[0].status(429).send("error - already queued");
    return;
  }
  console.log("enqueued", address);
  addressToRequest.set(address, 1);
  requestQueue.push([address, request]);
  requestQueueAdded();
};

async function agd(args) {
  try {
    console.log("Running agd ", ...args);
    const { stdout, stderr } = await spawnAsync("agd", args, {});
    console.log('stdout:', stdout);
    console.log('stderr:', stderr);
    return true;
  } catch (e) {
    console.error(e); // should contain code (exit code) and signal (that caused the termination).
    return false;
  }
}

const spawnAsync = async (
  command,
  args,
  options
) =>
  new Promise((resolve, reject) => {
    const spawnProcess = spawn(command, args, options);
    const chunks = [];
    const errorChunks = [];
    spawnProcess.stdout.on("data", (data) => {
      process.stdout.write(data.toString());
      chunks.push(data);
    });
    spawnProcess.stderr.on("data", (data) => {
      process.stderr.write(data.toString());
      errorChunks.push(data);
    });
    spawnProcess.on("error", (error) => {
      reject(error);
    });
    spawnProcess.on("close", (code) => {
      if (code === 1) {
        reject(Buffer.concat(errorChunks).toString());
        return;
      }
      resolve(Buffer.concat(chunks));
    });
  });

// Faucet worker.
const startFaucetWorker = () => {
  console.log('Starting Faucet worker!');
  (async () => {
  for await (const [address, request] of faucetRequests) {
    // Handle request.
    console.log("dequeued", address);

    const command = request[1];
    let status = false;
    switch (command){
      case "client": {
        status = await agd(["tx", "bank", "send", "-b", "block", process.env.WHALE_KEYNAME || "self", address, process.env.CLIENT_AMOUNT || "25000000urun",  "-y", "--keyring-backend", "test", "--home", process.env.AGORIC_HOME, "--chain-id", process.env.CHAIN_ID]);
        if (status){
          status = await agd(["tx", "swingset", "provision-one", "faucet_provision", address, "-b", "block", "--from", process.env.WHALE_KEYNAME, "-y", "--keyring-backend", "test", "--home", process.env.AGORIC_HOME, "--chain-id", process.env.CHAIN_ID]);
        }
        break;
      }
      case "delegate": {
        status = await agd(["tx", "bank", "send", "-b", "block", process.env.WHALE_KEYNAME || "self", address, process.env.DELEGATE_AMOUNT || "75000000ubld",  "-y", "--keyring-backend", "test", "--home", process.env.AGORIC_HOME, "--chain-id", process.env.CHAIN_ID]);
        break;
      }
      default: {
        console.log("unknown command");
        request[0].status(500).send("failure");
        continue;
      }
    }

    addressToRequest.delete(address);
    if (status){
      console.log("Success");
      request[0].status(200).send("success");
    } else {
      console.log("Failure");
      request[0].status(500).send("failure");
    }
  }
})().catch(e => {
  console.error('Faucet worker died', e);
  new Promise(resolve => setTimeout(resolve, 3000)).then(startFaucetWorker);
});
};
startFaucetWorker();

privateapp.listen(privateport, () => {
  console.log(`privateapp listening on port ${privateport}`)
});

faucetapp.get('/', (req, res) => {
    res.send(`
    <html><head><title>Faucet</title></head><body><h1>welcome to the faucet</h1>
    <form action="/go" method="post">
    <label for="address">Address:</label> <input id="address" name="address" type="text" /><br>
    Request: <input type="radio" id="delegate" name="command" value="delegate">
    <label for="delegate">delegate</label> 
    <input type="radio" id="client" name="command" value="client">
    <label for="client">client</label><br>

    <input type="submit" />
    </form></body></html>
    `);
  }
);

faucetapp.use(express.urlencoded({
  extended: true
}))


faucetapp.post('/go', (req, res) => {
  const {command, address} = req.body;

  if ((command === "client" || command === "delegate") && (typeof address === "string" && address.length === 45 && /^agoric1[0-9a-zA-Z]{38}$/.test(address))){
    addRequest(address, [res, command]);
  } else {
    res.status(403).send('invalid form');
  }
});


faucetapp.listen(faucetport, () => {
  console.log(`faucetapp listening on port ${faucetport}`)
});

(async () => {
  if (process.env.FAKE !== undefined) {
    dockerImage = "asdf:unknown";
  } else {
    const statefulSet = await makeSynchronousRequest(`https://kubernetes.default.svc/apis/apps/v1/namespaces/${namespace}/statefulsets/validator-primary`);
    dockerImage = JSON.parse(statefulSet).spec.template.spec.containers[0].image;
  }
  publicapp.listen(publicport, () => {
    console.log(`publicapp listening on port ${publicport}`)
  })  
})();
