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
