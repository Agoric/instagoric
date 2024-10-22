import bodyParser from 'body-parser';
import express from 'express';

const publicapp = express();
const publicport = 8001;

const logReq = (req, res, next) => {
  const time = Date.now();
  res.on('finish', () => {
    console.log(
      JSON.stringify({
        time,
        dur: Date.now() - time,
        method: req.method,
        forwarded: req.get('X-Forwarded-For'),
        ip: req.ip,
        url: req.originalUrl,
        status: res.statusCode,
      }),
    );
  });
  next();
};

publicapp.use(logReq);
publicapp.use(bodyParser.json({ limit: '50mb' }));

publicapp.post('/api/v1/logs', (req, res) => {
  console.log('Received logs:', JSON.stringify(req.body, null, 2));
  res.send('');
});

publicapp.listen(publicport, () => {
  console.log(`publicapp listening on port ${publicport}`);
});
