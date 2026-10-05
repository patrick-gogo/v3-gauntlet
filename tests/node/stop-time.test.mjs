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
