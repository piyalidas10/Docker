const http = require('http');

const PORT = process.env.PORT || 3000;
const APP_ENV = process.env.APP_ENV || 'development';

const server = http.createServer((req, res) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);

  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', env: APP_ENV }));
    return;
  }

  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end(`
    <html>
      <body>
        <h1>Hello from Kubernetes!</h1>
        <p>Environment: <strong>${APP_ENV}</strong></p>
        <p>Running on Pod: <strong>${process.env.HOSTNAME || 'unknown'}</strong></p>
      </body>
    </html>
  `);
});

server.listen(PORT, () => {
  console.log(`Server running on port ${PORT} in ${APP_ENV} mode`);
});
