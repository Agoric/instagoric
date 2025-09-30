// @ts-check

import express from 'express';
import { formatMillisecondsToDuration } from './util.js';

const faucetport = 8003;
const privateport = 8002;
const publicport = 8001;

/**
 * @type {import('express').RequestHandler}
 */
const logReq = (request, response, next) => {
  const time = Date.now();
  response.on('finish', () =>
    console.log(
      JSON.stringify({
        duration: formatMillisecondsToDuration(Date.now() - time),
        forwarded: request.get('X-Forwarded-For'),
        ip: request.ip,
        method: request.method,
        status: response.statusCode,
        time,
        url: request.originalUrl,
      }),
    ),
  );
  return next();
};

export const faucetapp = express();
export const publicapp = express();
export const privateapp = express();

faucetapp.use(logReq);
privateapp.use(logReq);
publicapp.use(logReq);

publicapp.use(express.json());
publicapp.use(express.urlencoded({ extended: true }));

faucetapp.listen(faucetport, () =>
  console.log(`faucetapp listening on port ${faucetport}`),
);
privateapp.listen(privateport, () =>
  console.log(`privateapp listening on port ${privateport}`),
);
publicapp.listen(publicport, () =>
  console.log(`publicapp listening on port ${publicport}`),
);
