import { request as makeRequest } from 'node:https';
import { createServer as createHttpServer } from 'node:http';
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../mobile/build/web', import.meta.url));
const api = new URL('https://kunde-backend-ty81.onrender.com');
const apiMethods = {
  GET: /^\/api\/v1\/(capabilities|me|admin\/(employees|me\/capabilities|auto\/(bookings|categories|complaints|jobs|specialists|venues)|(rides|deliveries)(\/[^/?]+)*))$/,
  POST: /^\/api\/v1\/(auth\/(otp\/(request|verify)|token\/refresh|logout)|admin\/(rides|deliveries)\/[^/?]+(\/[^/?]+)*|admin\/auto\/(specialists\/[^/?]+\/decision|complaints\/[^/?]+\/resolve))$/,
  PATCH: /^\/api\/v1\/admin\/auto\/(categories|venues)\/[^/?]+$/,
};
const contentTypes = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.woff2': 'font/woff2',
};

function passToDev(req, res, url) {
  if (!apiMethods[req.method]?.test(url.pathname)) {
    res.writeHead(404).end();
    return;
  }
  const headers = {};
  for (const name of ['authorization', 'content-type', 'content-length']) {
    if (req.headers[name]) headers[name] = req.headers[name];
  }
  const upstream = makeRequest(api, {
    path: url.pathname + url.search,
    method: req.method,
    headers,
    timeout: 95_000,
  }, (reply) => {
    for (const name of ['content-type', 'retry-after', 'x-correlation-id']) {
      if (reply.headers[name]) res.setHeader(name, reply.headers[name]);
    }
    res.writeHead(reply.statusCode);
    reply.pipe(res);
  });
  upstream.on('timeout', () => upstream.destroy());
  upstream.on('error', () => {
    if (!res.headersSent) res.writeHead(502).end();
    else res.destroy();
  });
  res.on('close', () => {
    if (!res.writableEnded) upstream.destroy();
  });
  req.pipe(upstream);
}

createHttpServer(async (req, res) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Cache-Control', 'no-store');
  try {
    const url = new URL(req.url, 'http://localhost');
    if (url.pathname.startsWith('/api/')) return passToDev(req, res, url);
    if (!['GET', 'HEAD'].includes(req.method)) return res.writeHead(405).end();
    const path = resolve(root, '.' + decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname));
    if (!path.startsWith(resolve(root) + sep)) return res.writeHead(404).end();
    const info = await stat(path);
    if (!info.isFile()) return res.writeHead(404).end();
    res.setHeader('Content-Type', contentTypes[extname(path)] ?? 'application/octet-stream');
    res.setHeader('Content-Length', info.size);
    if (req.method === 'HEAD') return res.end();
    const stream = createReadStream(path);
    stream.on('error', () => res.destroy());
    stream.pipe(res);
  } catch {
    res.writeHead(404).end();
  }
}).listen(Number(process.env.PORT ?? 8080), '0.0.0.0');
