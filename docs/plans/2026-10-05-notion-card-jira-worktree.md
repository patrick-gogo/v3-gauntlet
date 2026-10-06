# Notion card content, tracker status, worktree option: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the lap 1 lessons, and make the queue card the place to read a ticket (tracker text plus English, design, plan, rulings, lap handoff), move the tracker ticket to In Progress at intake, let local builds and push day stay out of the main checkout, and state the lap stop time as an explicit date.

**Architecture:** A small markdown-to-Notion-blocks converter (`notion-md.mjs`) feeds a new `page` command in `notion-queue.mjs` that replaces the card body or one named sub-page. The PLAN and lap skills call it at fixed points. Tracker status and push behaviour come from the private project config, so the plugin stays generic. A `stop-time.mjs` helper turns `HH:MM` + time zone into the next occurrence.

**Tech Stack:** Node 18+ (built-in `fetch`, `node:test`), bash 3.2 scripts, Claude Code skills (markdown).

**Spec:** this plan; the decisions it implements are in "Decisions" below (proposed 2026-10-05, defaults taken where the owner had not answered).

## Decisions (defaults used; owner may change before execution)
Task 7 (added 2026-10-05 after lap 1, at the owner's request) carries its own decisions.
1. The card **body** holds the ticket (tracker text verbatim, then `## English translation`); Design, Plan, Rulings and Handoff are **sub-pages** of the card.
2. The tracker ticket moves To Do -> In Progress **at intake** (PLAN step 2), only when it is assigned to the user and in To Do, without asking.
3. The card is created **at intake** with status Inbox (not only at Planned).
4. A **Handoff** sub-page is written after every `/v3-lap result`.
5. `checkout: worktree | main` in the project config; **default worktree**. Local BUILD then works in a worktree made with the `EnterWorktree` tool, never in the main checkout.
6. Push day never runs hooks in the main checkout: by default it pushes from a temporary worktree of the ticket branch; with `push_skip_hooks: yes` it pushes with `--no-verify` (the lap already ran the gates on the devbox).
7. The lead brief's stop time is a full local date and time (`2026-10-06 06:30 Asia/Manila`), the next occurrence after packing.

## Global Constraints
- Public repo: no employer names, hostnames, tracker URLs, chat IDs or ticket text in code, tests or docs. Project values live in the work project's `.claude/v3-gauntlet.md`.
- The board never blocks a stage: every Notion call that fails is reported in one line and the stage continues (exit 3 = could-not-run).
- Tokens are never printed (the client already replaces the token in error text with `***`).
- `notion-queue.mjs` uses `process.exitCode`, never `process.exit()` (aborts Node on Windows after a fetch).
- Notion API version stays `2022-06-28`. Limits to respect: 100 blocks per append request, 2000 characters per rich-text item, block nesting not needed.
- Bash scripts run on macOS bash 3.2 and Git Bash; quote every path (paths may contain spaces).
- Conventional Commits, one commit per task, no tool attribution.

## Review Focus
1. A plan or design longer than 100 blocks: must be appended in chunks of 100, in order, with nothing lost.
2. A paragraph or code block longer than 2000 characters: must be split into several rich-text items, not rejected by the API.
3. Re-running the same `page` call (PLAN resumed, rulings batch 2): must replace the sub-page content, never create a second "Plan" page.
4. Japanese text in the ticket body: must arrive unchanged (UTF-8 end to end on Windows).
5. Stop time when packing after midnight but before the stop time (e.g. 02:00 with stop 06:30): must be the same day, not tomorrow.

---

## File structure
- Create `skills/ticket-workspace/scripts/notion-md.mjs`: `markdownToBlocks(md) -> block[]` (pure, no I/O).
- Modify `skills/ticket-workspace/scripts/notion-queue.mjs`: add the `page` command.
- Create `skills/lap/scripts/stop-time.mjs`: `nextStop(now, hhmm, tz) -> "YYYY-MM-DD HH:MM"`, CLI `node stop-time.mjs 06:30 Asia/Manila`.
- Tests: `tests/node/notion-md.test.mjs`, `tests/node/notion-page.test.mjs`, `tests/node/stop-time.test.mjs`, each run by a `tests/scripts/*.test.sh` wrapper (same pattern as `tests/scripts/notion-queue.test.sh`).
- Skills: `ticket-plan/SKILL.md` (intake card + body, tracker status, sub-pages, checkout), `ticket-workspace/SKILL.md` (config keys and sections), `ticket-build/SKILL.md` (worktree entry), `lap/SKILL.md` (handoff sub-page, push without main-checkout hooks, stop time), `lap/templates/lead-brief.md`.
- Docs: README, `docs/HANDOFF.md`, `.claude-plugin/plugin.json` (0.4.0).

---

### Task 1: Markdown to Notion blocks

**Files:**
- Create: `skills/ticket-workspace/scripts/notion-md.mjs`
- Test: `tests/node/notion-md.test.mjs`, `tests/scripts/notion-md.test.sh`

**Interfaces:**
- Produces: `export function markdownToBlocks(md: string): object[]` returning Notion block objects of types `heading_1`, `heading_2`, `heading_3`, `paragraph`, `bulleted_list_item`, `numbered_list_item`, `code`, `quote`, `divider`. Tables (`| a | b |` lines) become `code` blocks with language `plain text` (simple, readable, no nesting). Every rich-text array has items of at most 2000 characters.

- [ ] **Step 1: Write the failing tests**

```js
// tests/node/notion-md.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { markdownToBlocks } from '../../skills/ticket-workspace/scripts/notion-md.mjs';

const textOf = (b) => b[b.type].rich_text.map((t) => t.text.content).join('');

test('headings, paragraphs, lists, quote, divider', () => {
  const b = markdownToBlocks('# T\n## H2\n### H3\nPara one\nstill para\n\n- a\n- b\n1. x\n2. y\n> q\n---\n');
  assert.deepEqual(b.map((x) => x.type), ['heading_1', 'heading_2', 'heading_3', 'paragraph', 'bulleted_list_item', 'bulleted_list_item', 'numbered_list_item', 'numbered_list_item', 'quote', 'divider']);
  assert.equal(textOf(b[3]), 'Para one still para');
  assert.equal(textOf(b[6]), 'x');
});

test('fenced code keeps its content and language', () => {
  const b = markdownToBlocks('```js\nconst a = 1;\n  indented\n```\n');
  assert.equal(b.length, 1);
  assert.equal(b[0].type, 'code');
  assert.equal(b[0].code.language, 'javascript');
  assert.equal(textOf(b[0]), 'const a = 1;\n  indented');
});

test('unknown fence language falls back to plain text', () => {
  assert.equal(markdownToBlocks('```weird\nx\n```')[0].code.language, 'plain text');
});

test('a table becomes one plain-text code block', () => {
  const b = markdownToBlocks('| a | b |\n|---|---|\n| 1 | 2 |\n');
  assert.equal(b.length, 1);
  assert.equal(b[0].type, 'code');
  assert.equal(textOf(b[0]), '| a | b |\n|---|---|\n| 1 | 2 |');
});

test('text longer than 2000 characters is split into several items', () => {
  const long = 'x'.repeat(4500);
  const b = markdownToBlocks(long);
  const items = b[0].paragraph.rich_text;
  assert.equal(items.length, 3);
  assert.ok(items.every((t) => t.text.content.length <= 2000));
  assert.equal(textOf(b[0]).length, 4500);
});

test('Japanese text is kept as is', () => {
  assert.equal(textOf(markdownToBlocks('プレビューの取得に失敗しました')[0]), 'プレビューの取得に失敗しました');
});

test('empty input gives no blocks', () => {
  assert.deepEqual(markdownToBlocks(''), []);
});
```

```bash
# tests/scripts/notion-md.test.sh
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
out=$(node --test "$ROOT/tests/node/notion-md.test.mjs" 2>&1); code=$?
assert_eq 0 "$code" "notion-md node tests pass"
[ "$code" -eq 0 ] || echo "$out" | tail -40
finish
```

- [ ] **Step 2: Run to verify they fail**
Run: `node --test tests/node/notion-md.test.mjs`
Expected: FAIL, cannot find module `notion-md.mjs`.

- [ ] **Step 3: Implement**

```js
// skills/ticket-workspace/scripts/notion-md.mjs
// Turn the plugin's markdown (tickets, plans, rulings, handoffs) into Notion blocks.
// Deliberately small: headings, paragraphs, lists, quotes, dividers, fenced code; tables become code blocks.
const LIMIT = 2000;
const LANGS = { js: 'javascript', javascript: 'javascript', ts: 'typescript', typescript: 'typescript', tsx: 'typescript',
  bash: 'bash', sh: 'shell', shell: 'shell', python: 'python', py: 'python', json: 'json', sql: 'sql', yaml: 'yaml',
  md: 'markdown', markdown: 'markdown', html: 'html', css: 'css', diff: 'diff' };

function rich(text) {
  const out = [];
  for (let i = 0; i < text.length; i += LIMIT) out.push({ type: 'text', text: { content: text.slice(i, i + LIMIT) } });
  return out.length ? out : [{ type: 'text', text: { content: '' } }];
}
const block = (type, text, extra = {}) => ({ object: 'block', type, [type]: { rich_text: rich(text), ...extra } });

export function markdownToBlocks(md) {
  const lines = String(md).replace(/\r\n/g, '\n').split('\n');
  const blocks = [];
  let para = [];
  const flush = () => { if (para.length) { blocks.push(block('paragraph', para.join(' '))); para = []; } };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const fence = line.match(/^```\s*(\S*)\s*$/);
    if (fence) {
      flush();
      const body = [];
      while (++i < lines.length && !/^```\s*$/.test(lines[i])) body.push(lines[i]);
      blocks.push(block('code', body.join('\n'), { language: LANGS[fence[1].toLowerCase()] || 'plain text' }));
      continue;
    }
    if (/^\s*\|.*\|\s*$/.test(line)) {
      flush();
      const rows = [line];
      while (i + 1 < lines.length && /^\s*\|.*\|\s*$/.test(lines[i + 1])) rows.push(lines[++i]);
      blocks.push(block('code', rows.join('\n'), { language: 'plain text' }));
      continue;
    }
    let m;
    if (line.trim() === '') { flush(); continue; }
    if (/^(---|\*\*\*)\s*$/.test(line)) { flush(); blocks.push({ object: 'block', type: 'divider', divider: {} }); continue; }
    if ((m = line.match(/^(#{1,3})\s+(.*)$/))) { flush(); blocks.push(block(`heading_${m[1].length}`, m[2])); continue; }
    if ((m = line.match(/^\s*[-*]\s+(.*)$/))) { flush(); blocks.push(block('bulleted_list_item', m[1])); continue; }
    if ((m = line.match(/^\s*\d+[.)]\s+(.*)$/))) { flush(); blocks.push(block('numbered_list_item', m[1])); continue; }
    if ((m = line.match(/^>\s?(.*)$/))) { flush(); blocks.push(block('quote', m[1])); continue; }
    para.push(line.trim());
  }
  flush();
  return blocks;
}
```

- [ ] **Step 4: Run to verify they pass**
Run: `node --test tests/node/notion-md.test.mjs` then `bash tests/scripts/notion-md.test.sh`
Expected: all pass.

- [ ] **Step 5: Commit**
```bash
git add skills/ticket-workspace/scripts/notion-md.mjs tests/node/notion-md.test.mjs tests/scripts/notion-md.test.sh
git commit -m "feat: convert plugin markdown to Notion blocks"
```

---

### Task 2: `page` command (card body and named sub-pages)

**Files:**
- Modify: `skills/ticket-workspace/scripts/notion-queue.mjs` (new command, usage line, header comment)
- Test: `tests/node/notion-page.test.mjs`, `tests/scripts/notion-page.test.sh`

**Interfaces:**
- Consumes: `markdownToBlocks(md)` from Task 1; the existing `client`, `findByKey`, `loadConfig`, `main(argv, deps)`.
- Produces: CLI `node notion-queue.mjs page --key K --file <md> [--child "<Title>"]`. Without `--child`: replaces the card body (every child block that is **not** a `child_page` is deleted, then the new blocks are appended). With `--child`: finds the card's `child_page` block whose title equals `<Title>`; if found, deletes its children and appends; if not, creates the page (`POST /v1/pages` with `parent: { page_id: <card id> }` and title) and appends. Prints `page <card body|Title> <id> (<n> blocks)`. Exit codes as the rest: 1 key not in queue, 2 bad input (missing file, missing args), 3 could-not-run. `deps` gains nothing new: the file is read with the existing `deps.readFile`.

- [ ] **Step 1: Write the failing tests**

```js
// tests/node/notion-page.test.mjs
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
    { json: {} },              // DELETE b1
    { json: { results: [] } }, // PATCH append
  ]);
  assert.equal(r.code, 0);
  assert.equal(r.calls[1].method, 'GET'); assert.match(r.calls[1].url, /\/blocks\/card1\/children/);
  assert.equal(r.calls[2].method, 'DELETE'); assert.match(r.calls[2].url, /\/blocks\/b1$/);
  assert.equal(r.calls[3].method, 'PATCH'); assert.match(r.calls[3].url, /\/blocks\/card1\/children$/);
  assert.deepEqual(r.calls[3].body.children.map((b) => b.type), ['heading_1', 'paragraph']);
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
    { json: {} },              // DELETE old1
    { json: { results: [] } }, // PATCH append to sp
  ]);
  assert.equal(r.code, 0);
  assert.ok(!r.calls.some((c) => c.method === 'POST'), 'no new page');
  assert.match(r.calls[3].url, /\/blocks\/old1$/);
  assert.match(r.calls[4].url, /\/blocks\/sp\/children$/);
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
```

The wrapper `tests/scripts/notion-page.test.sh` is the Task 1 wrapper with `notion-page.test.mjs`.

- [ ] **Step 2: Run to verify they fail**
Run: `node --test tests/node/notion-page.test.mjs`
Expected: FAIL (`page` is not a known command: exit 2 with usage).

- [ ] **Step 3: Implement** (inside `notion-queue.mjs`)

```js
import { markdownToBlocks } from './notion-md.mjs';

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
async function replaceBlocks(call, id, blocks, keep = () => false) {
  for (const b of await listChildren(call, id)) if (!keep(b)) await call('DELETE', `/blocks/${b.id}`);
  for (let i = 0; i < blocks.length; i += 100) await call('PATCH', `/blocks/${id}/children`, { children: blocks.slice(i, i + 100) });
}
```

In `main`: accept `page` in the command list; require `--key` and `--file` (`page needs --key and --file`); read the file **before** loading config or calling the API (`cannot read <file>` → exit 2). After `findByKey` (missing → exit 1):
- no `--child`: `replaceBlocks(call, card.id, blocks, (b) => b.type === 'child_page')`; out `page card body <id> (<n> blocks)`.
- `--child T`: `const sub = (await listChildren(call, card.id)).find((b) => b.type === 'child_page' && b.child_page?.title === T)`; id = sub ? sub.id : `(await call('POST', '/pages', { parent: { page_id: card.id }, properties: { title: { title: [{ text: { content: T } }] } } })).id`; `replaceBlocks(call, id, blocks)`; out `page <T> <id> (<n> blocks)`.
Update the usage string and the header comment with the `page` form.

- [ ] **Step 4: Run to verify they pass**
Run: `node --test tests/node/notion-page.test.mjs tests/node/notion-queue.test.mjs`
Expected: all pass (the 16 existing tests still pass).

- [ ] **Step 5: Live check on the real board** (laptop with `notion.env`)
Run: `printf '# Live check\n\nアイウ\n' > /tmp/p.md && node skills/ticket-workspace/scripts/notion-queue.mjs page --key TEST-1 --file /tmp/p.md --child "Plan"` twice.
Expected: exit 0 both times; the TEST-1 card has exactly one "Plan" sub-page showing the heading and the Japanese line.

- [ ] **Step 6: Commit**
```bash
git add skills/ticket-workspace/scripts/notion-queue.mjs tests/node/notion-page.test.mjs tests/scripts/notion-page.test.sh
git commit -m "feat: write the ticket and its sub-pages onto the queue card"
```

---

### Task 3: PLAN fills the card and moves the tracker ticket

**Files:**
- Modify: `skills/ticket-plan/SKILL.md` (steps 2, 5, 6, 8, 9), `skills/ticket-workspace/SKILL.md` (config: `## Tracker status` section; `card` state key)
- Test: `tests/scripts/validate.test.sh` (unchanged; run `scripts/validate.sh`)

**Interfaces:**
- Consumes: `page` from Task 2; `upsert`/`status` (existing).
- Produces: state key `card: done` (the card exists); config section `## Tracker status` (free text: how to move the user's own To Do ticket to In Progress).

- [ ] **Step 1: Edit `ticket-plan/SKILL.md`**
- Step 2 (intake), new sub-steps after the translation:
  - **4. Card:** with `queue: notion`, look for the key in `$Q list` first. No card → `$Q upsert --key <id> --title "<title>" --status Inbox`. A card already exists (the user added it to Inbox, or PLAN is resuming) → `$Q upsert --key <id> --title "<title>"` with no `--status`, so its column is left alone. Then `$Q page --key <id> --file WS/ticket.md`. `S set card done`. Exit 3 → one line, continue.
  - **5. Tracker status:** if `CFG` has `## Tracker status`, follow it: when the ticket is assigned to the user and in To Do, move it to In Progress and read the status back; anything else (already In Progress, someone else's ticket, the call fails) → one line in the ledger, continue. Never ask.
- Step 5.2, after `S phase designed`: `$Q page --key <id> --file WS/design.md --child Design`.
- Step 6, after `S phase planned`: `$Q page --key <id> --file WS/plan.md --child Plan`.
- Step 8.1, after writing the batch: `$Q page --key <id> --file WS/rulings.md --child Rulings`; step 8.3 after recording answers: the same call again (so the page shows `source: user`).
- Step 9.2: the `upsert ... --status Planned` stays; add `--branch`.
- Every `$Q` call: exit 3 is reported in one line and never stops PLAN (Global Constraints).

- [ ] **Step 2: Edit `ticket-workspace/SKILL.md`**
Add to the config block:
```
## Tracker status
<how to move the user's own To Do ticket to In Progress at intake; free text, read on the laptop>
```
and `card` to the state keys (`done` once the queue card exists).

- [ ] **Step 3: Validate**
Run: `bash scripts/validate.sh` and `bash tests/run.sh`
Expected: no new failures (the 4 known Windows-only ones stay).

- [ ] **Step 4: Commit**
```bash
git add skills/ticket-plan/SKILL.md skills/ticket-workspace/SKILL.md
git commit -m "feat: put the ticket, design, plan and rulings on the queue card and start the tracker ticket"
```

---

### Task 4: Lap handoff sub-page and an explicit stop time

**Files:**
- Create: `skills/lap/scripts/stop-time.mjs`
- Modify: `skills/lap/SKILL.md` (start step 2 and 6, result step 3), `skills/lap/templates/lead-brief.md`
- Test: `tests/node/stop-time.test.mjs`, `tests/scripts/stop-time.test.sh`

**Interfaces:**
- Produces: `export function nextStop(nowMs: number, hhmm: string, tz: string): string` returning `"YYYY-MM-DD HH:MM"` in `tz`, the first such time strictly after `nowMs`; CLI `node stop-time.mjs <HH:MM> <tz>` prints it (exit 2 on a bad time or zone).

- [ ] **Step 1: Write the failing tests**

```js
// tests/node/stop-time.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { nextStop } from '../../skills/lap/scripts/stop-time.mjs';
const at = (iso) => Date.parse(iso);

test('afternoon packing: stop is tomorrow morning', () => {
  assert.equal(nextStop(at('2026-10-05T05:14:00Z'), '06:30', 'Asia/Manila'), '2026-10-06 06:30'); // 13:14 Manila
});
test('after midnight but before the stop: same day', () => {
  assert.equal(nextStop(at('2026-10-05T18:00:00Z'), '06:30', 'Asia/Manila'), '2026-10-06 06:30'); // 02:00 Manila on the 6th
});
test('exactly at the stop time: the next day', () => {
  assert.equal(nextStop(at('2026-10-05T22:30:00Z'), '06:30', 'Asia/Manila'), '2026-10-07 06:30');
});
test('another zone', () => {
  assert.equal(nextStop(at('2026-10-05T12:00:00Z'), '07:00', 'Asia/Tokyo'), '2026-10-06 07:00'); // 21:00 Tokyo
});
test('bad input throws', () => {
  assert.throws(() => nextStop(Date.now(), '25:00', 'Asia/Manila'));
  assert.throws(() => nextStop(Date.now(), '06:30', 'Not/AZone'));
});
```

- [ ] **Step 2: Run to verify they fail**
Run: `node --test tests/node/stop-time.test.mjs` → FAIL (module missing).

- [ ] **Step 3: Implement**

```js
// skills/lap/scripts/stop-time.mjs
// The next HH:MM in a time zone after now, as "YYYY-MM-DD HH:MM", so a lead brief never says just "06:30".
import { pathToFileURL } from 'node:url';

function partsIn(ms, tz) {
  const f = new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
  const p = Object.fromEntries(f.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
  return { date: `${p.year}-${p.month}-${p.day}`, minutes: Number(p.hour) * 60 + Number(p.minute) };
}

export function nextStop(nowMs, hhmm, tz) {
  const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(hhmm);
  if (!m) throw new Error(`bad time: ${hhmm}`);
  const target = Number(m[1]) * 60 + Number(m[2]);
  const now = partsIn(nowMs, tz); // throws RangeError for an unknown zone
  const day = now.minutes < target ? now.date : partsIn(nowMs + 24 * 3600 * 1000, tz).date;
  return `${day} ${hhmm}`;
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) {
  try { console.log(nextStop(Date.now(), process.argv[2], process.argv[3])); }
  catch (e) { console.error(String(e.message || e)); process.exitCode = 2; }
}
```

- [ ] **Step 4: Run to verify they pass**
Run: `node --test tests/node/stop-time.test.mjs` → all pass.

- [ ] **Step 5: Edit the lap skill and brief template**
- `lap/SKILL.md` start step 2: `STOP=$(node "$SKILL_DIR/scripts/stop-time.mjs" <lap_stop_time> <lap_timezone>)`; step 6 fills `{stop_time}` with `$STOP`.
- `lead-brief.md`: `- Stop time: do not start a new ticket after {stop_time} ({timezone}). This is a date and time, not a daily time.`
- `lap/SKILL.md` result step 3, after saving the handoff: for each ticket, `$Q page --key <id> --file "$LR/handoff.md" --child "Handoff <lap>"` (exit 3 → one line).
- All paths in the skill's commands are double-quoted (lap 1 broke on a folder name with a space).

- [ ] **Step 6: Commit**
```bash
git add skills/lap/scripts/stop-time.mjs tests/node/stop-time.test.mjs tests/scripts/stop-time.test.sh skills/lap/SKILL.md skills/lap/templates/lead-brief.md
git commit -m "fix: give the lap stop time as a date and put the handoff on the card"
```

---

### Task 5: Worktree option for local builds; push day outside the main checkout

**Files:**
- Modify: `skills/ticket-workspace/SKILL.md` (config keys `checkout`, `push_skip_hooks`), `skills/ticket-plan/SKILL.md` step 4.3, `skills/ticket-build/SKILL.md` step 0, `skills/ticket-ship/SKILL.md` step 3.3, `skills/lap/SKILL.md` push step 5
- Test: `bash scripts/validate.sh`, `bash tests/run.sh`; a manual dry run (below)

**Interfaces:**
- Produces: config keys `checkout: worktree | main` (default `worktree`) and `push_skip_hooks: yes | no` (default `no`); state `checkout` becomes `worktree` (until BUILD creates it) or the worktree path.

- [ ] **Step 1: Edit the skills**
- `ticket-plan` step 4.3: `S set checkout <CFG checkout, default worktree>` instead of always `main`.
- `ticket-build` step 0, before the branch check: when `checkout` is `worktree`, call the `EnterWorktree` tool with `name` = the ticket ID (it creates the worktree under `.claude/worktrees/` and moves the session into it), then `git switch -c <branch> <base>` there (or `git switch <branch>` if it exists), and `S set checkout <the worktree path>`. When `checkout` is a path, enter it (existing Worktrees rule). Only `main` works in the main checkout. Add `.claude/worktrees/` to `$(git rev-parse --git-common-dir)/info/exclude` once.
- `ticket-ship` 3.3 and `lap` push step 5: never let a push run hooks in the main checkout. `push_skip_hooks: yes` → `git push --no-verify -u origin <branch>` (state in the PR body that the project's gates ran in the lap or BUILD). Otherwise → `git worktree add "<tmp>" <branch>`, run `git -C "<tmp>" push -u origin <branch>` so hooks run there, then `git worktree remove --force "<tmp>"`; if the hook fails there for setup reasons (dependencies missing), report it and stop for that ticket, never retry in the main checkout.
- `ticket-workspace`: document both keys.

- [ ] **Step 2: Dry run (no push)**
In a scratch clone with a dummy `pre-push` hook that writes its `$PWD` to a file: create a branch, follow the default path with `git -C "<tmp>" push --dry-run`, and confirm the hook's recorded directory is the temporary worktree, not the main checkout.

- [ ] **Step 3: Validate and commit**
```bash
bash scripts/validate.sh; bash tests/run.sh
git add skills/ticket-workspace/SKILL.md skills/ticket-plan/SKILL.md skills/ticket-build/SKILL.md skills/ticket-ship/SKILL.md skills/lap/SKILL.md
git commit -m "feat: build in a worktree by default and keep push hooks out of the main checkout"
```

---

### Task 6: Docs, version, and the private config

**Files:**
- Modify: `README.md` (queue card contents, tracker status, checkout option, push behaviour), `docs/HANDOFF.md` (done list, caveats), `.claude-plugin/plugin.json` (0.4.0)
- Outside the repo (not committed): the work project's `.claude/v3-gauntlet.md` gains `checkout: worktree`, `push_skip_hooks: yes` and a `## Tracker status` section naming the tracker's transition calls.

- [ ] **Step 1: Write the docs** (no employer names; describe "the tracker").
- [ ] **Step 2: Scan before committing:** `grep -rniE "<employer and person names, hostnames, IDs>" README.md docs skills tests` returns nothing; `git diff | bash skills/ticket-workspace/scripts/secret-scan.sh -` reports only known false positives.
- [ ] **Step 3: Commit**
```bash
git add README.md docs/HANDOFF.md .claude-plugin/plugin.json
git commit -m "docs: describe the queue card, tracker status and worktree option, release 0.4.0"
```

---

### Task 7: Lap 1 lessons

Lap 1 (2026-10-05) worked end to end and showed six fixes. Decisions:
- **Author:** the devbox commits as its default user (`<user> <user@devbox.local>`). The brief carries the laptop's `git config user.name` / `user.email`, and the lead sets them in every worktree at GO. `lap-check.sh --author <email>` refuses a branch with any commit by another author. Push day re-authors unpublished lap commits only when `--author` fails and nothing else does.
- **No attribution in the rails:** the lead told a helper to add a co-author trailer and had to amend it out; the rule was only in the project's house rules. It becomes rail 13 of `RULES.md`.
- **`origin/<base>` for tools:** the devbox has no remote; the frontend ratchet needs `refs/remotes/origin/master`. At GO the lead creates `refs/remotes/origin/<base_branch>` at `BASE` and deletes it at cleanup.
- **Baseline runs every gate**, browser checks included, on `BASE` (lap 1 skipped the smoke test on the base).
- **Batch replies:** `ruling-reply.sh` accepts ranges (`1-5 keep`) and `yes` / `no` answers (for yes/no questions); its output adds `<n> yes` / `<n> no` lines.
- **Readable questions:** handoff section 0, the PLAN batch and `/v3-lap result` show one block per question (title and level, then Question / Pick / Why on their own lines), the last line giving the reply to accept every pick.

**Files:**
- Modify: `skills/ticket-workspace/scripts/ruling-reply.sh`, `tests/scripts/ruling-reply.test.sh`
- Modify: `skills/lap/scripts/lap-check.sh`, `tests/scripts/lap-check.test.sh`
- Modify: `skills/lap/templates/RULES.md` (rail 13; GO: identity + origin ref; 2.2 baseline every gate incl. browser checks; cleanup removes the ref; section 8 block layout), `skills/lap/templates/lead-brief.md` (`{git_name}`, `{git_email}`), `skills/lap/SKILL.md` (step 6 fills the identity; result step 5 block layout; push step 1 `--author`, re-author rule), `skills/ticket-plan/SKILL.md` (step 8 block layout)

**Interfaces:**
- `ruling-reply.sh <n> "<reply>"`: also prints `<k> yes` / `<k> no`; `a-b <verb>` applies the verb to every number from a to b.
- `lap-check.sh <branch> <base> [--snapshot <sha>] [--author <email>]`: with `--author`, every commit in `base..branch` must have that author email, else `not safe` with `author <email> on <short sha>` lines.

- [ ] **Step 1: Failing tests for the parser** (append to `tests/scripts/ruling-reply.test.sh` before `finish`)

```bash
out=$(bash "$S" 7 "1-5 keep. 6 yes 7 no"); code=$?
assert_eq 0 "$code" "ranges and yes/no answers"
assert_eq "1 keep
2 keep
3 keep
4 keep
5 keep
6 yes
7 no" "$out" "a range expands, yes/no pass through"

out=$(bash "$S" 3 "1-2 change: use the modal 3 keep"); code=$?
assert_eq 0 "$code" "a range with change text"
assert_eq "1 change use the modal
2 change use the modal
3 keep" "$out" "change text applies to the whole range"

out=$(bash "$S" 3 "2-5 keep 1 keep" 2>&1); code=$?
assert_eq 2 "$code" "a range past the last ruling is refused"
assert_contains "$out" "no ruling 4" "names the first unknown number"

out=$(bash "$S" 2 "1 yes please 2 no" 2>&1); code=$?
assert_eq 2 "$code" "yes/no take no text"
```

- [ ] **Step 2: Failing tests for the author check** (append to `tests/scripts/lap-check.test.sh` before `finish`)

```bash
git switch -qc bugfix/T-6-author "$BASE"; echo e >> app.txt
git -c user.name=devbox -c user.email=devbox@devbox.local commit -qam "fix(T-6): By the devbox"
out=$(bash "$C" bugfix/T-6-author "$BASE" --author t@example.com 2>&1); code=$?
assert_eq 1 "$code" "a commit by another author fails with --author"
assert_contains "$out" "author devbox@devbox.local on" "names the wrong author"
out=$(bash "$C" bugfix/T-1-good "$BASE" --author t@example.com); code=$?
assert_eq 0 "$code" "the right author passes"
out=$(bash "$C" bugfix/T-1-good "$BASE" --snapshot "$BASE" --author t@example.com 2>&1); code=$?
assert_eq 1 "$code" "--snapshot and --author work together"
```

- [ ] **Step 3: Run both test files, confirm the new checks fail**
Run: `bash tests/scripts/ruling-reply.test.sh; bash tests/scripts/lap-check.test.sh`
Expected: the new checks FAIL (ranges and yes/no are "say keep or change"; `--author` is ignored).

- [ ] **Step 4: Implement**
- `ruling-reply.sh`: add `yes` / `no` to the verb function; a verb of `yes` / `no` takes no text (like keep) and prints `<n> yes` / `<n> no`; before tokenising, expand `a-b` tokens (digits, a hyphen, digits, optional trailing `.`) into the numbers a..b, each followed by the next verb and its text. A number above the count is `no ruling <n>`. Keep bash 3.2 and BSD awk compatibility.
- `lap-check.sh`: parse `--snapshot` and `--author` in any order after the two positionals; with `--author`, `git log --format='%ae %h' base..branch` and add `author <email> on <sha>` for each mismatch.

- [ ] **Step 5: Run both test files, confirm they pass; run `bash tests/run.sh` once** (only the 4 known Windows-only failures).

- [ ] **Step 6: Templates and skills**
- `RULES.md` rail 13: "**No tool attribution, ever.** No co-author trailers, no 'Generated with' lines, in any commit, by you or any helper. Never ask a helper to add one."
- `RULES.md` 2.1 GO, new items: "Set the commit identity from the brief in every worktree you make: `git -C <worktree> config user.name "<git_name>"` and `user.email "<git_email>"`." and "Some project tools compare against `origin/<base_branch>`; there is no remote here, so create it: `git update-ref refs/remotes/origin/<base_branch> $BASE`. Delete it at cleanup (`git update-ref -d ...`)."
- `RULES.md` 2.2.3: "every gate in the Gates section, browser checks included" on `BASE`.
- `RULES.md` section 8, question format: one block per question: `**<n>. <short title>** · <T-level or follow-up or decision>` then `- **Question:** ...`, `- **Pick:** ...`, `- **Why:** ...`, and a closing line `To accept every pick: <the reply>`.
- `lead-brief.md`: a line `- Commit identity: {git_name} <{git_email}>. Set it in every worktree before the first commit.`
- `lap/SKILL.md` start step 6: fill `{git_name}` / `{git_email}` from the main checkout's `git config user.name` / `user.email`. Result step 5: show section 0 in the block layout above (rewrite it if the handoff did not use it). Push step 1: `lap-check.sh "$R" <base> --author <git_email>`; when the only failures are `author` lines, re-author in the temporary worktree before pushing: `git -C "<tmp>" -c user.name="<git_name>" -c user.email="<git_email>" rebase -q --exec 'git commit --amend --no-edit --reset-author' <base>` (the commits were never published, so nothing shared is rewritten), then run `lap-check.sh` again on the re-authored branch; any other failure still skips the ticket.
- `ticket-plan/SKILL.md` step 8.1: the batch uses the same block layout.

- [ ] **Step 7: Commit**
```bash
git add skills/ticket-workspace/scripts/ruling-reply.sh tests/scripts/ruling-reply.test.sh skills/lap/scripts/lap-check.sh tests/scripts/lap-check.test.sh skills/lap/templates/RULES.md skills/lap/templates/lead-brief.md skills/lap/SKILL.md skills/ticket-plan/SKILL.md
git commit -m "fix: apply lap 1 lessons (commit identity, no attribution rail, origin ref, full baseline, replies, question layout)"
```

---

## After execution (not code)
- Backfill the lap 1 ticket: `page` its ticket, design, plan and rulings onto its card; move its tracker ticket to In Progress.
- When lap 1 returns, `/v3-lap result` writes the first Handoff sub-page.
