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
