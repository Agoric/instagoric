var fs = require('fs');
var path = require('path');

const https = require('https');

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
  res.send(`
<html><head><title>Instagoric</title></head><body><pre>
██╗███╗   ██╗███████╗████████╗ █████╗  ██████╗  ██████╗ ██████╗ ██╗ ██████╗
██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██╔════╝ ██╔═══██╗██╔══██╗██║██╔════╝
██║██╔██╗ ██║███████╗   ██║   ███████║██║  ███╗██║   ██║██████╔╝██║██║     
██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║   ██║██║   ██║██╔══██╗██║██║     
██║██║ ╚████║███████║   ██║   ██║  ██║╚██████╔╝╚██████╔╝██║  ██║██║╚██████╗
╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝ ╚═════╝

Chain: ` + (process.env.CHAIN_ID || "unknown") + `
Network Config: <a href="https://` + (process.env.NETNAME || "devnet" ) + (process.env.NETDOMAIN || ".agoric.net" ) + `/network-config">https://` + (process.env.NETNAME || "devnet" ) + (process.env.NETDOMAIN || ".agoric.net" ) + `/network-config</a>
RPC: <a href="https://` + (process.env.NETNAME || "devnet" ) + `.rpc` +  (process.env.NETDOMAIN || ".agoric.net") + `">https://` + (process.env.NETNAME || "devnet" ) + `.rpc` +  (process.env.NETDOMAIN || ".agoric.net") + `</a>
gRPC: <a href="https://` + (process.env.NETNAME || "devnet" ) + `.grpc` +  (process.env.NETDOMAIN || ".agoric.net") + `">https://` + (process.env.NETNAME || "devnet" ) + `.grpc` +  (process.env.NETDOMAIN || ".agoric.net") + `</a>
API: <a href="https://` + (process.env.NETNAME || "devnet" ) + `.api` +  (process.env.NETDOMAIN || ".agoric.net") + `">https://` + (process.env.NETNAME || "devnet" ) + `.api` +  (process.env.NETDOMAIN || ".agoric.net") + `</a>
Explorer: <a href="https://` + (process.env.NETNAME || "devnet" ) + `.explorer` +  (process.env.NETDOMAIN || ".agoric.net") + `">https://` + (process.env.NETNAME || "devnet" ) + `.explorer` +  (process.env.NETDOMAIN || ".agoric.net") + `</a>
Faucet: <a href="https://` + (process.env.NETNAME || "devnet" ) + `.faucet` +  (process.env.NETDOMAIN || ".agoric.net") + `">https://` + (process.env.NETNAME || "devnet" ) + `.faucet` +  (process.env.NETDOMAIN || ".agoric.net") + `</a>

</pre></body></html>                                                     
  `)
})

publicapp.get('/network-config', (req, res) => {
  networkConfig.getData()
    .then((result) => {
      res.send(result);
    });
})

publicapp.listen(publicport, () => {
  console.log(`publicapp listening on port ${publicport}`)
})

privateapp.get('/', (req, res) => {
  res.send('welcome to instagoric');
})

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
})

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
})

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

privateapp.listen(privateport, () => {
  console.log(`publicapp listening on port ${privateport}`)
})

faucetapp.get('/', (req, res) => {
  res.send('welcome to faucet');
})

faucetapp.listen(faucetport, () => {
  console.log(`faucetapp listening on port ${faucetport}`)
})
