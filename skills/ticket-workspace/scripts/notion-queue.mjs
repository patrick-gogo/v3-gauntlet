#!/usr/bin/env node
// Read and update the ticket queue, a Notion database, through the Notion API.
// Usage: node notion-queue.mjs check
//        node notion-queue.mjs list [--status <s>]           -> TSV: order key status title page_id
//        node notion-queue.mjs upsert --key K --title T [--status S] [--repo R] [--branch B] [--notes N] [--report URL]
//        node notion-queue.mjs status --key K --status S [--branch B] [--notes N] [--report URL]
//        node notion-queue.mjs page --key K --file <md> [--child "<Title>"]   -> replace the card body, or the named sub-page, with the markdown
// Config: NOTION_TOKEN and GAUNTLET_QUEUE_DB from the environment, else KEY=value lines in
// ${V3_GAUNTLET_NOTION_ENV:-~/.config/v3-gauntlet/notion.env}. Never stored in a repo.
// Exit: 0 ok, 1 key not in the queue, 2 bad input or ambiguous rows, 3 could-not-run (no token, network, API error).
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { markdownToBlocks } from './notion-md.mjs';

export const STATUSES = ['Inbox', 'Planned', 'Queued', 'Running', 'Needs you', 'Ready', 'PR open', 'Done'];
const API = 'https://api.notion.com/v1';
const NOTION_VERSION = '2022-06-28';

class CouldNotRun extends Error {}
class BadInput extends Error {}

export function loadConfig(env, readFile) {
  let token = env.NOTION_TOKEN, db = env.GAUNTLET_QUEUE_DB;
  if (!token || !db) {
    const path = env.V3_GAUNTLET_NOTION_ENV || join(env.HOME || env.USERPROFILE || homedir(), '.config', 'v3-gauntlet', 'notion.env');
    let text = '';
    try { text = readFile(path); } catch { text = ''; }
    for (const line of text.split(/\r?\n/)) {
      const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/);
      if (!m) continue;
      if (m[1] === 'NOTION_TOKEN' && !token) token = m[2];
      if (m[1] === 'GAUNTLET_QUEUE_DB' && !db) db = m[2];
    }
  }
  return { token, db };
}

function parseArgs(argv) {
  const [cmd, ...rest] = argv;
  const opts = {};
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (!a.startsWith('--') || i + 1 >= rest.length) throw new BadInput(`bad argument: ${a}`);
    opts[a.slice(2)] = rest[++i];
  }
  return { cmd, opts };
}

const text = (v) => ({ rich_text: [{ text: { content: v } }] });
const plain = (arr) => (arr || []).map((t) => t.plain_text).join('');

function props(opts, withTitle) {
  const p = {};
  if (withTitle) {
    p.Ticket = { title: [{ text: { content: `${opts.key} ${opts.title}` } }] };
    p.Key = text(opts.key);
  }
  if (opts.status) p.Status = { select: { name: opts.status } };
  if (opts.repo) p.Repo = { select: { name: opts.repo } };
  if (opts.branch) p.Branch = text(opts.branch);
  if (opts.notes) p.Notes = text(opts.notes);
  if (opts.report) p.Report = { url: opts.report };
  return p;
}

const MAX_ATTEMPTS = 5;
const MAX_BODY_BYTES = 400000; // Notion rejects request bodies over 500KB; stay well under
const realSleep = (ms) => new Promise((r) => setTimeout(r, ms));

// 429 and 5xx are retried up to MAX_ATTEMPTS times: wait Retry-After seconds when the header is there, else 0.5s, 1s, 2s, 4s.
function client({ token, fetch, sleep = realSleep }) {
  return async (method, path, body) => {
    for (let attempt = 1; ; attempt++) {
      let res;
      try {
        res = await fetch(API + path, {
          method,
          headers: { Authorization: `Bearer ${token}`, 'Notion-Version': NOTION_VERSION, 'Content-Type': 'application/json' },
          body: body ? JSON.stringify(body) : undefined,
        });
      } catch (e) {
        throw new CouldNotRun(String(e.message || e).replaceAll(token, '***'));
      }
      let data = {};
      try { data = await res.json(); } catch { data = {}; }
      if (res.ok) return data;
      if ((res.status === 429 || res.status >= 500) && attempt < MAX_ATTEMPTS) {
        const secs = Number(res.headers?.get?.('retry-after'));
        await sleep(Number.isFinite(secs) && secs >= 0 && res.headers.get('retry-after') !== '' ? secs * 1000 : 500 * 2 ** (attempt - 1));
        continue;
      }
      throw new CouldNotRun(`HTTP ${res.status}: ${String(data.message || 'no message').replaceAll(token, '***')}`);
    }
  };
}

async function query(call, db, filter) {
  const rows = [];
  let cursor;
  do {
    const body = {};
    if (filter) body.filter = filter;
    if (cursor) body.start_cursor = cursor;
    const page = await call('POST', `/databases/${db}/query`, body);
    rows.push(...(page.results || []));
    cursor = page.has_more ? page.next_cursor : undefined;
  } while (cursor);
  return rows;
}

function toRow(p) {
  const key = plain(p.properties?.Key?.rich_text);
  let title = plain(p.properties?.Ticket?.title);
  if (title.startsWith(key + ' ')) title = title.slice(key.length + 1);
  return { id: p.id, key, title, status: p.properties?.Status?.select?.name || '', order: p.properties?.Order?.number ?? null, created: p.created_time || '' };
}

async function findByKey(call, db, key) {
  const rows = await query(call, db, { property: 'Key', rich_text: { equals: key } });
  if (rows.length > 1) throw new BadInput(`${rows.length} rows have key ${key}; fix the queue by hand`);
  return rows[0];
}

async function listChildren(call, id) {
  const all = []; let cursor;
  do {
    const q = cursor ? `?start_cursor=${cursor}&page_size=100` : '?page_size=100';
    const r = await call('GET', `/blocks/${id}/children${q}`);
    all.push(...(r.results || []));
    cursor = r.has_more ? r.next_cursor : undefined;
  } while (cursor);
  return all;
}

// Split blocks into append requests of at most 100 blocks and MAX_BODY_BYTES of JSON.
function chunkBlocks(blocks) {
  const chunks = [];
  let cur = [], bytes = 0;
  for (const b of blocks) {
    const size = Buffer.byteLength(JSON.stringify(b)) + 1;
    if (cur.length && (cur.length >= 100 || bytes + size > MAX_BODY_BYTES)) { chunks.push(cur); cur = []; bytes = 0; }
    cur.push(b); bytes += size;
  }
  if (cur.length) chunks.push(cur);
  return chunks;
}

async function replaceBlocks(call, id, blocks, keep = () => false, fresh = false) {
  // Append first, delete after: a failed append must not leave the page empty.
  const children = fresh ? [] : await listChildren(call, id);
  const old = children.filter((b) => !keep(b));
  const chunks = chunkBlocks(blocks);
  // Sub-page links must stay below the body. The append endpoint only adds to the end unless given `after`, so when a
  // sub-page exists the new blocks go after the last old body block above the first sub-page. Every chunk uses that same
  // anchor and the chunks are sent last-first, so each one lands in front of the previous and the final order is correct.
  // If the sub-page is the very first block there is no anchor to insert after and the body is appended at the end.
  const firstPage = children.findIndex((b) => keep(b));
  const anchor = firstPage > 0 ? children[firstPage - 1].id : undefined;
  if (anchor) {
    for (const chunk of chunks.reverse()) await call('PATCH', `/blocks/${id}/children`, { children: chunk, after: anchor });
  } else {
    for (const chunk of chunks) await call('PATCH', `/blocks/${id}/children`, { children: chunk });
  }
  for (const b of old) await call('DELETE', `/blocks/${b.id}`);
}

const USAGE = 'usage: notion-queue.mjs check | list [--status S] | upsert --key K --title T [--status S] [--repo R] [--branch B] [--notes N] [--report URL] | status --key K --status S [...] | page --key K --file F [--child T]';

export async function main(argv, deps) {
  const { env, fetch, readFile, out, err, sleep } = deps;
  try {
    const { cmd, opts } = parseArgs(argv);
    if (!['check', 'list', 'upsert', 'status', 'page'].includes(cmd)) throw new BadInput(USAGE);
    if (opts.status && !STATUSES.includes(opts.status)) throw new BadInput(`unknown status: ${opts.status} (one of: ${STATUSES.join(', ')})`);
    if (cmd === 'upsert' && (!opts.key || !opts.title)) throw new BadInput('upsert needs --key and --title');
    if (cmd === 'status' && (!opts.key || !opts.status)) throw new BadInput('status needs --key and --status');

    let blocks;
    if (cmd === 'page') {
      if (!opts.key || !opts.file) throw new BadInput('page needs --key and --file');
      let md;
      try { md = readFile(opts.file); } catch { throw new BadInput(`cannot read ${opts.file}`); }
      blocks = markdownToBlocks(md);
      if (!blocks.length) throw new BadInput(`${opts.file} has no content`);
    }

    const { token, db } = loadConfig(env, readFile);
    if (!token || !db) throw new CouldNotRun('no token or database id: set NOTION_TOKEN and GAUNTLET_QUEUE_DB, or write them to ~/.config/v3-gauntlet/notion.env');
    const call = client({ token, fetch, sleep });

    if (cmd === 'check') {
      const d = await call('GET', `/databases/${db}`);
      out(`NOTION: ok (${plain(d.title) || 'untitled'})`);
      return 0;
    }
    if (cmd === 'list') {
      const rows = (await query(call, db, opts.status ? { property: 'Status', select: { equals: opts.status } } : undefined)).map(toRow);
      rows.sort((a, b) => (a.order ?? Infinity) - (b.order ?? Infinity) || a.created.localeCompare(b.created));
      for (const r of rows) out([r.order ?? '-', r.key, r.status, r.title, r.id].join('\t'));
      return 0;
    }
    if (cmd === 'page') {
      const card = await findByKey(call, db, opts.key);
      if (!card) { err(`not in the queue: ${opts.key}`); return 1; }
      let id, label;
      if (opts.child) {
        const sub = (await listChildren(call, card.id)).find((b) => b.type === 'child_page' && b.child_page?.title === opts.child);
        id = sub ? sub.id : (await call('POST', '/pages', { parent: { page_id: card.id }, properties: { title: { title: [{ text: { content: opts.child } }] } } })).id;
        label = opts.child;
        await replaceBlocks(call, id, blocks, undefined, !sub);
      } else {
        id = card.id; label = 'card body';
        await replaceBlocks(call, id, blocks, (b) => b.type === 'child_page');
      }
      out(`page ${label} ${id} (${blocks.length} blocks)`);
      return 0;
    }
    const existing = await findByKey(call, db, opts.key);
    if (cmd === 'upsert') {
      if (existing) {
        await call('PATCH', `/pages/${existing.id}`, { properties: props(opts, true) });
        out(`updated ${existing.id}`);
      } else {
        const created = await call('POST', '/pages', { parent: { database_id: db }, properties: props(opts, true) });
        out(`created ${created.id}`);
      }
      return 0;
    }
    if (!existing) { err(`not in the queue: ${opts.key}`); return 1; }
    await call('PATCH', `/pages/${existing.id}`, { properties: props(opts, false) });
    out(`updated ${existing.id}`);
    return 0;
  } catch (e) {
    if (e instanceof CouldNotRun) { err(`NOTION: could-not-run (${e.message})`); return 3; }
    if (e instanceof BadInput) { err(e.message.startsWith('usage') ? e.message : `${e.message}\n${USAGE}`); return 2; }
    throw e;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) {
  // exitCode, not exit(): exiting while fetch's socket is still closing aborts Node on Windows.
  process.exitCode = await main(process.argv.slice(2), {
    env: process.env, fetch: globalThis.fetch,
    readFile: (p) => readFileSync(p, 'utf8'),
    out: (s) => console.log(s), err: (s) => console.error(s),
  });
}
