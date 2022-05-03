var http = require('http');
var fs = require('fs');
var path = require('path');

const https = require('https');

const namespace = fs.readFileSync("/var/run/secrets/kubernetes.io/serviceaccount/namespace", {encoding:'utf8', flag:'r'});


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

const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

// anonymous async function to execute some code synchronously after http request
(async function () {
  var svc = null;

  while (true) {
    try {
      svc = await getServices();
    } catch {}
    if (svc != null && svc.keys.length >= 0) {
        break;
    }
    await delay(4000);
  }

  http.createServer(function (request, response) {

    var file = "/network-config";
    var authrequired = false;
    var buf = "";
    switch (request.url) {
      case "/network-config":
        file = "/config/network/network_info.json";
        buf = fs.readFileSync(file, {encoding:'utf8', flag:'r'});
        var ap = JSON.parse(buf);
        ap.chainName = process.env.CHAIN_ID;
        ap.gci = "http://" + (svc.get('rpcnodes-ext') || "rpcnodes.instagoric.svc.cluster.local") + ":26657/genesis";
        ap.peers[0] = ap.peers[0].replace("validator-primary.instagoric.svc.cluster.local", (svc.get('validator-primary-ext') || "validator-primary.instagoric.svc.cluster.local"));
        var rpcs = [];
        for (const it of ['rpcnodes-ext']) {
          if (svc.get(it) !== undefined) {
            rpcs.push(svc.get(it) + ":26657");
          }
        }
        ap.seeds[0] = ap.seeds[0].replace("seed.instagoric.svc.cluster.local", (svc.get('seed-ext') || "seed.instagoric.svc.cluster.local"));
        ap.rpcAddrs = rpcs;
        buf = JSON.stringify(ap);
        break;
      case "/ips":
        buf = JSON.stringify({status: 1, ips: Object.fromEntries(svc)});
        break;
      case "/repl":
        authrequired = true;
        file = "/state/agoric.repl";
        buf = fs.readFileSync(file, {encoding:'utf8', flag:'r'});
        buf = buf.replace("127.0.0.1", svc.get('ag-solo-manual-ext') || "127.0.0.1");
        break;   
      case "/genesis.json":
        file = `/state/${process.env.CHAIN_ID}/config/genesis_final.json`;
        buf = fs.readFileSync(file, {encoding:'utf8', flag:'r'});
        break;   
      default:
        response.writeHead(200, { 'Content-Type': 'text/html' });
        response.end(".", 'utf-8');
        return;
    }

    if (authrequired){
      const userpass = Buffer.from(
        (request.headers.authorization || '').split(' ')[1] || '',
        'base64'
      ).toString();
      if (userpass !== 'agoric:notasecret') {
        response.writeHead(401, { 'WWW-Authenticate': 'Basic realm="nope"' });
        response.end('HTTP Error 401 Unauthorized: Access is denied');
          return;
      }
    }

    response.end(buf, 'utf-8');

  }).listen(8001);
  console.log('Server running at http://127.0.0.1:8001/');

})();

