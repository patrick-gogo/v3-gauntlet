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

const items = (b) => b[b.type].rich_text;

test('inline **bold** and `code` become annotations, not literal markers', () => {
  const b = markdownToBlocks('A **big** and `small` thing');
  assert.deepEqual(items(b[0]).map((t) => [t.text.content, t.annotations?.bold === true, t.annotations?.code === true]), [
    ['A ', false, false], ['big', true, false], [' and ', false, false], ['small', false, true], [' thing', false, false],
  ]);
});

test('inline annotations also apply in list items, headings and quotes', () => {
  const b = markdownToBlocks('- **x** item\n## `h` two\n> **q**');
  assert.equal(items(b[0])[0].annotations.bold, true);
  assert.equal(textOf(b[0]), 'x item');
  assert.equal(items(b[1])[0].annotations.code, true);
  assert.equal(items(b[2])[0].annotations.bold, true);
});

test('markers inside fenced code and tables stay literal', () => {
  assert.equal(textOf(markdownToBlocks('```\n**a** `b`\n```')[0]), '**a** `b`');
  assert.equal(textOf(markdownToBlocks('| **a** |')[0]), '| **a** |');
});

test('#### and deeper headings map to heading_3', () => {
  assert.deepEqual(markdownToBlocks('#### a\n###### b').map((x) => x.type), ['heading_3', 'heading_3']);
});

test('a nested list item stays a list item', () => {
  const b = markdownToBlocks('- top\n  - child\n    1. deep');
  assert.deepEqual(b.map((x) => x.type), ['bulleted_list_item', 'bulleted_list_item', 'numbered_list_item']);
  assert.equal(textOf(b[1]), 'child');
});

test('a block never carries more than 100 rich_text items', () => {
  const b = markdownToBlocks(Array.from({ length: 150 }, (_, i) => `**b${i}** `).join(''));
  assert.ok(b.length >= 2, 'split into several blocks');
  assert.ok(b.every((x) => items(x).length <= 100));
  assert.equal(b.map(textOf).join('').replace(/\s+/g, ''), Array.from({ length: 150 }, (_, i) => `b${i}`).join(''));
});

test('an oversized code block is split into several code blocks of the same language', () => {
  const b = markdownToBlocks('```js\n' + 'y'.repeat(2000 * 130) + '\n```');
  assert.ok(b.length >= 2);
  assert.ok(b.every((x) => x.type === 'code' && x.code.language === 'javascript' && x.code.rich_text.length <= 100));
  assert.ok(b.every((x) => x.code.rich_text.every((t) => t.text.content.length <= 2000)));
});

test('an unclosed fence at end of file is closed and stays a code block', () => {
  const b = markdownToBlocks('intro\n```js\nconst a = 1;\nmore');
  assert.deepEqual(b.map((x) => x.type), ['paragraph', 'code']);
  assert.equal(textOf(b[1]), 'const a = 1;\nmore');
});
