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
test('fall-back day (25 hours): tomorrow is the next calendar date', () => {
  // 00:30 EDT on 2026-11-01; adding 24h would land at 23:30 EST the same day.
  assert.equal(nextStop(at('2026-11-01T04:30:00Z'), '00:15', 'America/New_York'), '2026-11-02 00:15');
});
test('spring-forward day (23 hours): tomorrow is the next calendar date', () => {
  // 01:30 EST on 2026-03-08, stop 01:00.
  assert.equal(nextStop(at('2026-03-08T06:30:00Z'), '01:00', 'America/New_York'), '2026-03-09 01:00');
});
test('month and year ends roll over', () => {
  assert.equal(nextStop(at('2026-12-31T20:00:00Z'), '06:30', 'Asia/Manila'), '2027-01-01 06:30'); // 04:00 Manila on Jan 1: same day
  assert.equal(nextStop(at('2026-12-31T05:00:00Z'), '06:30', 'Asia/Manila'), '2027-01-01 06:30'); // 13:00 Manila Dec 31
});
test('a missing zone throws', () => {
  assert.throws(() => nextStop(Date.now(), '06:30', undefined), /zone/);
});
