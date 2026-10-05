import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadConfig, main, STATUSES } from '../../skills/ticket-workspace/scripts/notion-queue.mjs';

// A fake fetch that records requests and answers from a queue of canned responses.
function fakeFetch(responses) {
  const calls = [];
  const fn = async (url, opts = {}) => {
    calls.push({ url, method: opts.method || 'GET', headers: opts.headers || {}, body: opts.body ? JSON.parse(opts.body) : undefined });
    const r = responses.shift();
    if (!r) throw new Error('unexpected request: ' + url);
    if (r.throw) throw new Error(r.throw);
    return { ok: (r.status || 200) < 300, status: r.status || 200, json: async () => r.json };
  };
  fn.calls = calls;
  return fn;
}

function row(id, key, status, order, title = 'Some title', created = '2026-10-05T00:00:00.000Z') {
  return {
    id, created_time: created,
    properties: {
      Key: { rich_text: [{ plain_text: key }] },
      Ticket: { title: [{ plain_text: `${key} ${title}` }] },
      Status: { select: status ? { name: status } : null },
      Order: { number: order },
    },
  };
}

async function run(args, { env = { NOTION_TOKEN: 'secret-token', GAUNTLET_QUEUE_DB: 'db1' }, responses = [], file = null } = {}) {
  const out = [], err = [];
  const fetch = fakeFetch(responses);
  const code = await main(args, {
    env, fetch,
    readFile: (p) => { if (file === null) throw Object.assign(new Error('nope'), { code: 'ENOENT' }); return file; },
    out: (s) => out.push(s), err: (s) => err.push(s),
  });
  return { code, out: out.join('\n'), err: err.join('\n'), calls: fetch.calls };
}

test('loadConfig prefers env, falls back to the config file, ignores comments', () => {
  assert.deepEqual(loadConfig({ NOTION_TOKEN: 't', GAUNTLET_QUEUE_DB: 'd' }, () => ''), { token: 't', db: 'd' });
  const file = '# comment\nNOTION_TOKEN=ftok\nGAUNTLET_QUEUE_DB = fdb\n';
  assert.deepEqual(loadConfig({ HOME: '/h' }, () => file), { token: 'ftok', db: 'fdb' });
});

test('no token: could-not-run, exit 3, and no request is made', async () => {
  const r = await run(['list'], { env: { HOME: '/h' } });
  assert.equal(r.code, 3);
  assert.match(r.err, /NOTION: could-not-run \(no token/);
  assert.equal(r.calls.length, 0);
});

test('list --status Queued filters by status, sorts by Order then creation, prints TSV', async () => {
  const r = await run(['list', '--status', 'Queued'], {
    responses: [{ json: { results: [
      row('p3', 'V3-3', 'Queued', null, 'Third'),
      row('p2', 'V3-2', 'Queued', 2, 'Second'),
      row('p1', 'V3-1', 'Queued', 1, 'First'),
    ], has_more: false } }],
  });
  assert.equal(r.code, 0);
  assert.equal(r.calls[0].method, 'POST');
  assert.match(r.calls[0].url, /\/v1\/databases\/db1\/query$/);
  assert.deepEqual(r.calls[0].body.filter, { property: 'Status', select: { equals: 'Queued' } });
  assert.equal(r.calls[0].headers.Authorization, 'Bearer secret-token');
  assert.ok(r.calls[0].headers['Notion-Version']);
  assert.equal(r.out, ['1\tV3-1\tQueued\tFirst\tp1', '2\tV3-2\tQueued\tSecond\tp2', '-\tV3-3\tQueued\tThird\tp3'].join('\n'));
});

test('list follows pagination', async () => {
  const r = await run(['list'], {
    responses: [
      { json: { results: [row('p1', 'V3-1', 'Inbox', 1)], has_more: true, next_cursor: 'c2' } },
      { json: { results: [row('p2', 'V3-2', 'Inbox', 2)], has_more: false } },
    ],
  });
  assert.equal(r.code, 0);
  assert.equal(r.calls[1].body.start_cursor, 'c2');
  assert.equal(r.out.split('\n').length, 2);
});

test('upsert creates a row when the key is new', async () => {
  const r = await run(['upsert', '--key', 'V3-9', '--title', 'Fix cart', '--status', 'Planned', '--branch', 'bugfix/V3-9-fix-cart'], {
    responses: [{ json: { results: [], has_more: false } }, { json: { id: 'new1' } }],
  });
  assert.equal(r.code, 0);
  assert.deepEqual(r.calls[0].body.filter, { property: 'Key', rich_text: { equals: 'V3-9' } });
  const create = r.calls[1];
  assert.equal(create.method, 'POST');
  assert.match(create.url, /\/v1\/pages$/);
  assert.deepEqual(create.body.parent, { database_id: 'db1' });
  assert.equal(create.body.properties.Ticket.title[0].text.content, 'V3-9 Fix cart');
  assert.equal(create.body.properties.Key.rich_text[0].text.content, 'V3-9');
  assert.deepEqual(create.body.properties.Status, { select: { name: 'Planned' } });
  assert.equal(create.body.properties.Branch.rich_text[0].text.content, 'bugfix/V3-9-fix-cart');
  assert.equal(r.out, 'created new1');
});

test('upsert updates the existing row instead of adding a duplicate', async () => {
  const r = await run(['upsert', '--key', 'V3-9', '--title', 'Fix cart', '--status', 'Planned'], {
    responses: [{ json: { results: [row('old1', 'V3-9', 'Inbox', 3)], has_more: false } }, { json: { id: 'old1' } }],
  });
  assert.equal(r.code, 0);
  assert.equal(r.calls[1].method, 'PATCH');
  assert.match(r.calls[1].url, /\/v1\/pages\/old1$/);
  assert.equal(r.out, 'updated old1');
});

test('status moves an existing row and can set the report link', async () => {
  const r = await run(['status', '--key', 'V3-9', '--status', 'Running', '--report', 'https://example.com/r'], {
    responses: [{ json: { results: [row('old1', 'V3-9', 'Queued', 1)], has_more: false } }, { json: { id: 'old1' } }],
  });
  assert.equal(r.code, 0);
  assert.deepEqual(r.calls[1].body.properties, { Status: { select: { name: 'Running' } }, Report: { url: 'https://example.com/r' } });
});

test('status on an unknown key exits 1 and changes nothing', async () => {
  const r = await run(['status', '--key', 'V3-404', '--status', 'Running'], { responses: [{ json: { results: [], has_more: false } }] });
  assert.equal(r.code, 1);
  assert.match(r.err, /not in the queue: V3-404/);
  assert.equal(r.calls.length, 1);
});

test('two rows with the same key are refused (exit 2) rather than guessing', async () => {
  const r = await run(['status', '--key', 'V3-9', '--status', 'Running'], {
    responses: [{ json: { results: [row('a', 'V3-9', 'Queued', 1), row('b', 'V3-9', 'Inbox', 2)], has_more: false } }],
  });
  assert.equal(r.code, 2);
  assert.match(r.err, /2 rows have key V3-9/);
});

test('an unknown status is refused before any request', async () => {
  const r = await run(['status', '--key', 'V3-9', '--status', 'Doing']);
  assert.equal(r.code, 2);
  assert.match(r.err, /unknown status: Doing/);
  assert.equal(r.calls.length, 0);
  assert.ok(STATUSES.includes('Needs you'));
});

test('an API error is could-not-run (exit 3) and never prints the token', async () => {
  const r = await run(['list'], { responses: [{ status: 401, json: { message: 'API token is invalid.' } }] });
  assert.equal(r.code, 3);
  assert.match(r.err, /NOTION: could-not-run \(HTTP 401: API token is invalid\.\)/);
  assert.doesNotMatch(r.err + r.out, /secret-token/);
});

test('a network failure is could-not-run (exit 3)', async () => {
  const r = await run(['list'], { responses: [{ throw: 'getaddrinfo ENOTFOUND api.notion.com' }] });
  assert.equal(r.code, 3);
  assert.match(r.err, /NOTION: could-not-run \(getaddrinfo ENOTFOUND/);
});

test('check reads the database and reports its title', async () => {
  const r = await run(['check'], { responses: [{ json: { title: [{ plain_text: 'Gauntlet Queue' }] } }] });
  assert.equal(r.code, 0);
  assert.equal(r.calls[0].method, 'GET');
  assert.match(r.calls[0].url, /\/v1\/databases\/db1$/);
  assert.equal(r.out, 'NOTION: ok (Gauntlet Queue)');
});

test('the CLI does not call process.exit (it crashes Node on Windows after a fetch)', async () => {
  const { readFileSync } = await import('node:fs');
  const src = readFileSync(new URL('../../skills/ticket-workspace/scripts/notion-queue.mjs', import.meta.url), 'utf8');
  assert.doesNotMatch(src, /process\.exit\(/);
  assert.match(src, /process\.exitCode\s*=/);
});

test('the CLI exits with main\'s code (3 when there is no token)', async () => {
  const { spawnSync } = await import('node:child_process');
  const { fileURLToPath } = await import('node:url');
  const script = fileURLToPath(new URL('../../skills/ticket-workspace/scripts/notion-queue.mjs', import.meta.url));
  const r = spawnSync(process.execPath, [script, 'list'], {
    env: { PATH: process.env.PATH, V3_GAUNTLET_NOTION_ENV: '/nonexistent/notion.env' }, encoding: 'utf8',
  });
  assert.equal(r.status, 3);
  assert.match(r.stderr, /could-not-run/);
});

test('missing arguments and unknown commands exit 2 with usage', async () => {
  assert.equal((await run(['upsert', '--key', 'V3-1'])).code, 2);
  assert.equal((await run(['frobnicate'])).code, 2);
  assert.match((await run([])).err, /usage:/);
});
