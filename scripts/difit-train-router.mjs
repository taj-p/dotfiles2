#!/usr/bin/env node

// difit-train-router — makes a whole choochoo train reviewable behind one port.
//
// difit shows exactly one diff per process, so a train of N branches needs N
// difit servers. Exposing N ports would mean N Highway tunnels, and each new
// tunnel is a new hostname that reviewers have to be `infra highway allow`ed
// onto. So instead: one port, and this router picks the difit instance to talk
// to from a cookie.
//
// Routing has to be by cookie rather than by path prefix because difit's client
// asks for its assets at absolute paths (`/assets/index-*.js`), which a prefix
// would break. The upside is that those assets are byte-identical across
// instances of the same difit version, so only `/api/*` routing actually
// matters and a stale cookie can never render a broken page.
//
// Reads `choo show --json` on stdin. Prints its own port in the same shape
// difit prints, so difit-train.sh can scrape either one.

import { spawn } from 'node:child_process';
import http from 'node:http';

const PROG = 'difit-train';
const COOKIE = 'choo_pair';
// difit itself defaults to 4966; start above that so a plain `dfh` running
// alongside keeps its usual port. Every instance is asked for a distinct
// preferred port to keep two simultaneous binds from racing, and difit
// auto-assigns anyway if one is taken — the port we use is always the one it
// reports back.
const FIRST_PORT = 4970;
const START_TIMEOUT_MS = 20_000;

// Headers that describe a single hop and must not be forwarded, or Node will
// end up double-managing chunked encoding and connection reuse.
const HOP_BY_HOP = new Set([
  'connection',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
]);

function die(message) {
  process.stderr.write(`${PROG}: ${message}\n`);
  process.exit(1);
}

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf8');
}

/// One difit instance per branch, in stack order, with the aggregate last:
/// its diff is the whole train, which is the natural thing to look at after
/// the per-branch passes.
function planEntries(train) {
  const entries = train.branches.map((b) => ({
    branch: b.branch,
    parent: b.parent,
    pr: b.pr,
    combined: false,
  }));
  if (train.aggregate) {
    entries.push({
      branch: train.aggregate.branch,
      parent: train.aggregate.parent,
      pr: train.aggregate.pr,
      combined: true,
    });
  }
  return entries.map((e, i) => ({ ...e, position: i + 1 }));
}

/// Spawns difit for one pair and resolves once it has reported a port — or
/// once it's clear it never will. A branch that difit refuses (missing
/// locally, say) leaves `entry.error` set and the rest of the train usable,
/// rather than taking the whole session down.
function startInstance(entry, preferredPort) {
  const args = [
    entry.branch,
    entry.parent,
    // A train that isn't currently restacked still gets a clean diff; for a
    // freshly rebased one this resolves to the parent's tip either way.
    '--merge-base',
    '--no-open',
    '--keep-alive',
    '--host',
    '127.0.0.1',
    '--port',
    String(preferredPort),
  ];
  const child = spawn('difit', args, { stdio: ['ignore', 'pipe', 'pipe'] });
  entry.child = child;

  return new Promise((resolve) => {
    let output = '';
    let settled = false;
    const finish = (port, error) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      entry.port = port;
      entry.error = error;
      resolve();
    };
    const timer = setTimeout(
      () => finish(undefined, 'timed out waiting for difit to start'),
      START_TIMEOUT_MS,
    );
    const onData = (chunk) => {
      output += chunk;
      const match = output.match(/server started on http:\/\/[^:]*:(\d+)/u);
      if (match) {
        finish(Number(match[1]), undefined);
      }
    };
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', onData);
    child.stderr.on('data', onData);
    child.once('error', (error) => finish(undefined, error.message));
    child.on('exit', (code) => {
      // Also covers a crash long after startup: the entry stops being
      // proxyable and the index page says why.
      entry.port = undefined;
      finish(undefined, firstLine(output) || `difit exited (code ${code ?? 'unknown'})`);
      entry.error ??= `difit exited (code ${code ?? 'unknown'})`;
    });
  });
}

function firstLine(text) {
  return text
    .split(/\r?\n/u)
    .map((line) => line.trim())
    .find((line) => line.length > 0 && !line.startsWith('🚀'));
}

function esc(text) {
  return String(text).replace(
    /[&<>"']/gu,
    (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c],
  );
}

// ---------------------------------------------------------------------------

const raw = await readStdin();
if (!raw.trim()) {
  die('no train on stdin; expected the output of `choo show --json`');
}
let train;
try {
  train = JSON.parse(raw);
} catch (error) {
  die(`could not parse the train on stdin: ${error.message}`);
}
const entries = planEntries(train);
if (entries.length === 0) {
  die(`train \`${train.name}\` has no branches; \`choo add <branch>\` to add one`);
}

// Started one at a time so their preferred ports can't collide, and so the
// progress lines come out in stack order.
for (const [i, entry] of entries.entries()) {
  await startInstance(entry, FIRST_PORT + i);
  const label = entry.combined ? `${entry.position}. ${entry.branch} (combined)` : `${entry.position}. ${entry.branch}`;
  const status = entry.port === undefined ? `unavailable — ${entry.error}` : `:${entry.port}`;
  process.stdout.write(`${PROG}: ${label}  vs  ${entry.parent}  ${status}\n`);
}

function entryFor(req) {
  const match = (req.headers.cookie ?? '').match(
    new RegExp(`(?:^|;\\s*)${COOKIE}=(\\d+)`, 'u'),
  );
  const position = match ? Number(match[1]) : 1;
  return entries[position - 1] ?? entries[0];
}

/// The bar injected into every difit page: three plain links, no inline
/// script, so nothing here can be broken by a future difit CSP. Stepping
/// through the train is the whole review workflow, so prev/next earn their
/// place over a bare index link.
function switcherHtml(entry) {
  const prev = entries[entry.position - 2];
  const next = entries[entry.position];
  const arrow = (target, glyph, title) =>
    target
      ? `<a class="choo-step" href="/_train/${target.position}" title="${esc(title)}: ${esc(target.branch)}">${glyph}</a>`
      : `<span class="choo-step choo-off">${glyph}</span>`;
  return `
<style>
  .choo-bar {
    position: fixed; bottom: 0; left: 0; z-index: 99999;
    display: flex; align-items: stretch; gap: 1px;
    font: 12px/1 ui-monospace, SFMono-Regular, Menlo, monospace;
    background: #1f2328; color: #e6edf3;
    border: 1px solid #3d444d; border-left: 0; border-bottom: 0;
    border-radius: 0 6px 0 0; overflow: hidden;
    box-shadow: 0 0 12px rgb(0 0 0 / 35%);
  }
  .choo-bar a, .choo-bar span { padding: 7px 9px; color: inherit; text-decoration: none; }
  .choo-bar a:hover { background: #2f363d; }
  .choo-off { opacity: 0.3; }
  .choo-where { max-width: 46ch; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .choo-count { opacity: 0.6; }
</style>
<div class="choo-bar">
  ${arrow(prev, '&#9664;', 'previous')}
  <a class="choo-where" href="/_train" title="every branch in train ${esc(train.name)}"
    ><span class="choo-count">${entry.position}/${entries.length}</span> ${esc(entry.branch)}${entry.combined ? ' (combined)' : ''}</a>
  ${arrow(next, '&#9654;', 'next')}
</div>
`;
}

function indexHtml(current) {
  const rows = entries
    .map((entry) => {
      const here = entry === current;
      const pr = entry.pr
        ? `<a href="${esc(entry.pr.url)}">#${esc(entry.pr.number)}</a>`
        : '<span class="muted">no PR</span>';
      const status =
        entry.port === undefined
          ? `<span class="bad">unavailable — ${esc(entry.error ?? 'difit did not start')}</span>`
          : '';
      return `
      <tr${here ? ' class="here"' : ''}>
        <td class="num">${entry.position}</td>
        <td>
          <a class="branch" href="/_train/${entry.position}">${esc(entry.branch)}</a>
          ${entry.combined ? '<span class="tag">combined</span>' : ''}
          ${here ? '<span class="tag tag-here">viewing</span>' : ''}
          <div class="muted">vs ${esc(entry.parent)}</div>
          ${status}
        </td>
        <td>${pr}</td>
      </tr>`;
    })
    .join('');
  const context = train.context
    ? `<pre class="context">${esc(train.context)}</pre>`
    : '';
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(train.name)} — difit train</title>
<style>
  :root { color-scheme: light dark; }
  body {
    margin: 0; padding: 2.5rem 1.5rem; display: flex; justify-content: center;
    font: 15px/1.5 ui-sans-serif, system-ui, -apple-system, sans-serif;
  }
  main { width: 100%; max-width: 46rem; }
  h1 { font-size: 1.35rem; margin: 0 0 0.25rem; }
  .base { margin: 0 0 1.5rem; opacity: 0.7; font-size: 0.9rem; }
  .context {
    margin: 0 0 1.75rem; padding: 0.9rem 1rem; white-space: pre-wrap;
    font: inherit; background: color-mix(in srgb, currentColor 6%, transparent);
    border-radius: 6px;
  }
  table { width: 100%; border-collapse: collapse; }
  td { padding: 0.7rem 0.5rem; border-top: 1px solid color-mix(in srgb, currentColor 15%, transparent); vertical-align: top; }
  tr.here { background: color-mix(in srgb, currentColor 7%, transparent); }
  .num { width: 2rem; text-align: right; opacity: 0.5; font-variant-numeric: tabular-nums; }
  .branch { font-weight: 600; }
  .muted { opacity: 0.6; font-size: 0.85rem; }
  .bad { color: #d1242f; font-size: 0.85rem; }
  .tag {
    margin-left: 0.4rem; padding: 0.1rem 0.4rem; border-radius: 999px;
    font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.04em;
    background: color-mix(in srgb, currentColor 12%, transparent);
  }
  .tag-here { background: color-mix(in srgb, #1f883d 30%, transparent); }
  a { color: inherit; }
</style></head>
<body><main>
  <h1>${esc(train.name)}</h1>
  <p class="base">Each branch below is shown against its parent. Base: <code>${esc(train.base)}</code></p>
  ${context}
  <table>${rows}</table>
</main></body></html>
`;
}

function sendHtml(res, status, body, extraHeaders = {}) {
  const buffer = Buffer.from(body, 'utf8');
  res.writeHead(status, {
    'content-type': 'text/html; charset=utf-8',
    'content-length': buffer.length,
    'cache-control': 'no-store',
    ...extraHeaders,
  });
  res.end(buffer);
}

function proxy(req, res, entry, { injectSwitcher }) {
  if (entry.port === undefined) {
    sendHtml(
      res,
      502,
      `<!doctype html><meta charset="utf-8"><p>${esc(entry.branch)} is unavailable: ` +
        `${esc(entry.error ?? 'difit did not start')}</p>` +
        `<p><a href="/_train">back to the train</a></p>`,
    );
    return;
  }

  const headers = { ...req.headers, host: `127.0.0.1:${entry.port}` };
  for (const name of HOP_BY_HOP) {
    delete headers[name];
  }
  // Buffering to inject only works on an unencoded body, and this is the one
  // small HTML response in the session — everything else streams untouched.
  if (injectSwitcher) {
    headers['accept-encoding'] = 'identity';
  }

  const upstream = http.request(
    { host: '127.0.0.1', port: entry.port, method: req.method, path: req.url, headers },
    (up) => {
      const outHeaders = { ...up.headers };
      for (const name of HOP_BY_HOP) {
        delete outHeaders[name];
      }
      const isHtml = (up.headers['content-type'] ?? '').includes('text/html');
      if (!injectSwitcher || !isHtml) {
        res.writeHead(up.statusCode ?? 502, outHeaders);
        up.pipe(res);
        return;
      }
      const chunks = [];
      up.on('data', (chunk) => chunks.push(chunk));
      up.on('end', () => {
        const html = Buffer.concat(chunks).toString('utf8');
        const bar = switcherHtml(entry);
        const injected = html.includes('</body>')
          ? html.replace('</body>', `${bar}</body>`)
          : html + bar;
        const body = Buffer.from(injected, 'utf8');
        delete outHeaders['content-length'];
        res.writeHead(up.statusCode ?? 502, {
          ...outHeaders,
          'content-length': body.length,
        });
        res.end(body);
      });
    },
  );

  upstream.on('error', (error) => {
    if (!res.headersSent) {
      res.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' });
    }
    res.end(`${PROG}: upstream error: ${error.message}\n`);
  });
  // difit holds SSE connections open on /api/watch and /api/heartbeat; when the
  // browser drops one, the upstream request has to go with it.
  res.on('close', () => upstream.destroy());
  req.pipe(upstream);
}

const server = http.createServer((req, res) => {
  const path = (req.url ?? '/').split('?')[0];

  if (path === '/_train' || path === '/_train/') {
    sendHtml(res, 200, indexHtml(entryFor(req)));
    return;
  }

  const pick = path.match(/^\/_train\/(\d+)\/?$/u);
  if (pick) {
    const entry = entries[Number(pick[1]) - 1];
    if (!entry) {
      sendHtml(res, 404, '<!doctype html><meta charset="utf-8"><p>No such branch. <a href="/_train">Back to the train.</a></p>');
      return;
    }
    res.writeHead(302, {
      location: '/',
      'set-cookie': `${COOKIE}=${entry.position}; Path=/; SameSite=Lax`,
      'cache-control': 'no-store',
    });
    res.end();
    return;
  }

  proxy(req, res, entryFor(req), { injectSwitcher: req.method === 'GET' && path === '/' });
});

let shuttingDown = false;
function shutdown(signal) {
  if (shuttingDown) {
    return;
  }
  shuttingDown = true;
  server.close();
  for (const entry of entries) {
    entry.child?.kill(signal === 'SIGINT' ? 'SIGINT' : 'SIGTERM');
  }
  // Don't outlive the difit servers we exist to front — and don't hang either
  // if one of them declines to go, so this timer is deliberately not unref'd.
  setTimeout(() => process.exit(0), 1000);
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

server.listen(0, '127.0.0.1', () => {
  const { port } = server.address();
  // Deliberately phrased like difit's own banner so difit-train.sh can scrape
  // this line with the same expression it uses for a lone difit.
  process.stdout.write(`\n${PROG}: router server started on http://127.0.0.1:${port}\n`);
  process.stdout.write(`${PROG}: open http://127.0.0.1:${port}/_train\n`);
});
