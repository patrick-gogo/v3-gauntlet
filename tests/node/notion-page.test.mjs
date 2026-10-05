import { test } from 'node:test';
import assert from 'node:assert/strict';
import { main } from '../../skills/ticket-workspace/scripts/notion-queue.mjs';

function fakeFetch(responses) {
  const calls = [];
  const fn = async (url, opts = {}) => {
    calls.push({ url, method: opts.method || 'GET', body: opts.body ? JSON.parse(opts.body) : undefined });
    const r = responses.shift();
    if (!r) throw new Error('unexpected request: ' + (opts.method || 'GET') + ' ' + url);
    return { ok: (r.status || 200) < 300, status: r.status || 200, json: async () => r.json };
  };
  fn.calls = calls;
  return fn;
}
const card = { results: [{ id: 'card1', created_time: '', properties: { Key: { rich_text: [{ plain_text: 'V3-1' }] }, Ticket: { title: [{ plain_text: 'V3-1 t' }] }, Status: { select: { name: 'Inbox' } }, Order: { number: 1 } } }], has_more: false };
async function run(args, responses, file = '# Hello\n\nbody') {
  const out = [], err = [];
  const fetch = fakeFetch(responses);
  const code = await main(args, {
    env: { NOTION_TOKEN: 'tok', GAUNTLET_QUEUE_DB: 'db1' }, fetch,
    readFile: (p) => { if (p === 'missing.md') throw Object.assign(new Error('nope'), { code: 'ENOENT' }); return file; },
    out: (s) => out.push(s), err: (s) => err.push(s),
  });
  return { code, out: out.join('\n'), err: err.join('\n'), calls: fetch.calls };
}

test('body: deletes old non-page blocks, keeps sub-pages, appends new blocks', async () => {
  const r = await run(['page', '--key', 'V3-1', '--file', 'ticket.md'], [
    { json: card },
    { json: { results: [{ id: 'b1', type: 'paragraph' }, { id: 'sp', type: 'child_page', child_page: { title: 'Plan' } }], has_more: false } },
    { json: { results: [] } }, // PATCH append
    { json: {} },              // DELETE b1
  ]);
  assert.equal(r.code, 0);
  assert.equal(r.calls[1].method, 'GET'); assert.match(r.calls[1].url, /\/blocks\/card1\/children/);
  assert.equal(r.calls[2].method, 'PATCH'); assert.match(r.calls[2].url, /\/blocks\/card1\/children$/);
  assert.equal(r.calls[3].method, 'DELETE'); assert.match(r.calls[3].url, /\/blocks\/b1$/);
  assert.deepEqual(r.calls[2].body.children.map((b) => b.type), ['heading_1', 'paragraph']);
  assert.equal(r.calls.length, 4, 'the Plan sub-page is not deleted');
  assert.match(r.out, /page card body card1 \(2 blocks\)/);
});

test('child: creates the sub-page when missing, then appends', async () => {
  const r = await run(['page', '--key', 'V3-1', '--file', 'plan.md', '--child', 'Plan'], [
    { json: card },
    { json: { results: [{ id: 'b1', type: 'paragraph' }], has_more: false } },
    { json: { id: 'newpage' } }, // POST /pages
    { json: { results: [] } },   // PATCH append
  ]);
  assert.equal(r.code, 0);
  assert.equal(r.calls[2].method, 'POST'); assert.match(r.calls[2].url, /\/pages$/);
  assert.deepEqual(r.calls[2].body.parent, { page_id: 'card1' });
  assert.equal(r.calls[2].body.properties.title.title[0].text.content, 'Plan');
  assert.match(r.calls[3].url, /\/blocks\/newpage\/children$/);
});

test('child: replaces an existing sub-page instead of adding a second one', async () => {
  const r = await run(['page', '--key', 'V3-1', '--file', 'plan.md', '--child', 'Plan'], [
    { json: card },
    { json: { results: [{ id: 'sp', type: 'child_page', child_page: { title: 'Plan' } }], has_more: false } },
    { json: { results: [{ id: 'old1', type: 'paragraph' }], has_more: false } }, // children of sp
    { json: { results: [] } }, // PATCH append to sp
    { json: {} },              // DELETE old1
  ]);
  assert.equal(r.code, 0);
  assert.ok(!r.calls.some((c) => c.method === 'POST' && /\/pages$/.test(c.url)), 'no new page');
  assert.match(r.calls[3].url, /\/blocks\/sp\/children$/);
  assert.match(r.calls[4].url, /\/blocks\/old1$/);
});

test('a failed append deletes nothing', async () => {
  const r = await run(['page', '--key', 'V3-1', '--file', 'ticket.md'], [
    { json: card },
    { json: { results: [{ id: 'b1', type: 'paragraph' }], has_more: false } },
    { status: 500, json: { message: 'boom' } }, // PATCH append fails
  ]);
  assert.equal(r.code, 3);
  assert.ok(!r.calls.some((c) => c.method === 'DELETE'), 'no DELETE sent');
});

test('empty or whitespace-only markdown is bad input and makes no request', async () => {
  for (const content of ['', '  \n\n  ']) {
    const r = await run(['page', '--key', 'V3-1', '--file', 'empty.md'], [], content);
    assert.equal(r.code, 2);
    assert.match(r.err, /empty\.md has no content/);
    assert.equal(r.calls.length, 0);
  }
});

test('more than 100 blocks are appended in order, 100 at a time', async () => {
  const md = Array.from({ length: 230 }, (_, i) => `- item ${i}`).join('\n');
  const r = await run(['page', '--key', 'V3-1', '--file', 'big.md'], [
    { json: card }, { json: { results: [], has_more: false } },
    { json: {} }, { json: {} }, { json: {} },
  ], md);
  assert.equal(r.code, 0);
  const appends = r.calls.filter((c) => c.method === 'PATCH');
  assert.deepEqual(appends.map((c) => c.body.children.length), [100, 100, 30]);
  assert.equal(appends[2].body.children[29].bulleted_list_item.rich_text[0].text.content, 'item 229');
});

test('missing file is bad input and makes no request', async () => {
  const r = await run(['page', '--key', 'V3-1', '--file', 'missing.md'], []);
  assert.equal(r.code, 2);
  assert.match(r.err, /cannot read missing\.md/);
  assert.equal(r.calls.length, 0);
});

test('unknown key exits 1', async () => {
  const r = await run(['page', '--key', 'V3-9', '--file', 'x.md'], [{ json: { results: [], has_more: false } }]);
  assert.equal(r.code, 1);
});
