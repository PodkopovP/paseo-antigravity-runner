#!/usr/bin/env node
// ---------------------------------------------------------------------------
// Host-rewriting reverse proxy for the Antigravity hub language server.
//
// The standalone hub server binds 127.0.0.1 and *rejects any request whose
// Host header is not localhost/127.0.0.1 with 401* (a foreign Origin is fine;
// only Host is enforced). A Cloudflare Tunnel forwards traffic with the public
// tunnel hostname in Host, which the hub would reject. This proxy sits in
// front of it and rewrites Host (and Origin, defensively) to the loopback
// address for both plain HTTP and WebSocket upgrades, so the browser talks to
// `https://<tunnel-host>/` while the hub only ever sees `127.0.0.1`.
//
// No dependencies: Node core http + net only.
// ---------------------------------------------------------------------------

"use strict";

const http = require("http");
const net = require("net");

const LISTEN_HOST = process.env.PROXY_LISTEN_HOST || "0.0.0.0";
const LISTEN_PORT = parseInt(process.env.PROXY_LISTEN_PORT || "8765", 10);
const TARGET_HOST = process.env.HUB_HOST || "127.0.0.1";
const TARGET_PORT = parseInt(process.env.HUB_HTTP_PORT || "8090", 10);

const TARGET_AUTHORITY = `${TARGET_HOST}:${TARGET_PORT}`;
const TARGET_ORIGIN = `http://${TARGET_AUTHORITY}`;

// Rewrite the identity headers the hub inspects. Mutates in place.
function rewriteHeaders(headers) {
  headers.host = TARGET_AUTHORITY;
  if ("origin" in headers) headers.origin = TARGET_ORIGIN;
  if ("referer" in headers) {
    // Keep the path, swap the authority so any Referer check also passes.
    headers.referer = headers.referer.replace(
      /^https?:\/\/[^/]+/i,
      TARGET_ORIGIN,
    );
  }
  return headers;
}

const server = http.createServer((clientReq, clientRes) => {
  const headers = rewriteHeaders({ ...clientReq.headers });

  const upstream = http.request(
    {
      host: TARGET_HOST,
      port: TARGET_PORT,
      method: clientReq.method,
      path: clientReq.url,
      headers,
    },
    (upstreamRes) => {
      clientRes.writeHead(upstreamRes.statusCode, upstreamRes.headers);
      upstreamRes.pipe(clientRes);
    },
  );

  upstream.on("error", (err) => {
    if (!clientRes.headersSent) clientRes.writeHead(502, { "content-type": "text/plain" });
    clientRes.end(`proxy upstream error: ${err.message}\n`);
  });

  clientReq.pipe(upstream);
});

// WebSocket / raw upgrade handling: reconstruct the upgrade request with the
// rewritten Host/Origin and splice the two TCP sockets together.
server.on("upgrade", (req, clientSocket, head) => {
  const headers = rewriteHeaders({ ...req.headers });

  const upstream = net.connect(TARGET_PORT, TARGET_HOST, () => {
    let raw = `${req.method} ${req.url} HTTP/1.1\r\n`;
    for (const [key, value] of Object.entries(headers)) {
      const values = Array.isArray(value) ? value : [value];
      for (const v of values) raw += `${key}: ${v}\r\n`;
    }
    raw += "\r\n";
    upstream.write(raw);
    if (head && head.length) upstream.write(head);

    upstream.pipe(clientSocket);
    clientSocket.pipe(upstream);
  });

  const teardown = () => {
    upstream.destroy();
    clientSocket.destroy();
  };
  upstream.on("error", teardown);
  clientSocket.on("error", teardown);
  upstream.on("close", teardown);
  clientSocket.on("close", teardown);
});

server.listen(LISTEN_PORT, LISTEN_HOST, () => {
  console.log(
    `[proxy] listening on ${LISTEN_HOST}:${LISTEN_PORT} -> ${TARGET_ORIGIN} ` +
      `(Host/Origin rewritten to ${TARGET_AUTHORITY})`,
  );
});
