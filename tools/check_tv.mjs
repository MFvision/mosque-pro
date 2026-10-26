// Tests for the TV page's mosque timetable (website/tv/mosque.js) and the calculation options it passes to
// website/prayer.js: the iqama a mosque sets is the one the Adhan screen counts to, the Jumu'ah, Hanafi Asr and
// minute adjustments.
//
//     node tools/check_tv.mjs
import assert from 'node:assert/strict';
import { mosqueSettings, iqamaMinutes, adhanWindow, IQAMA_DEFAULTS } from '../website/tv/mosque.js';
import { schedule } from '../website/prayer.js';

const riyadh = { en: 'Riyadh', ar: 'الرياض', lat: 24.7136, lon: 46.6753, tz: 'Asia/Riyadh' };
// Thursday 15 and Friday 16 October 2026, at noon in Riyadh.
const thu = new Date('2026-10-15T09:00:00Z'), fri = new Date('2026-10-16T09:00:00Z');
const isFriday = (d) => new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Riyadh', weekday: 'short' }).format(d) === 'Fri';
const MIN = 60e3;
let passed = 0;
function test(name, fn) { fn(); passed++; console.log('ok', name); }
const time = (plan, k) => plan.today.find((x) => x[0] === k)[1];

test('nothing saved: the usual Saudi waits, the standard Asr, no minutes', () => {
  const s = mosqueSettings(null);
  assert.deepEqual(s.iqama, IQAMA_DEFAULTS);
  assert.equal(s.jumuah, 0);
  assert.equal(s.method, 'auto');
  assert.equal(s.asr, 'standard');
  assert.equal(s.offsets.isha, 0);
});

test('a broken or out-of-range save falls back to the defaults', () => {
  assert.deepEqual(mosqueSettings('{not json').iqama, IQAMA_DEFAULTS);
  const s = mosqueSettings(JSON.stringify({ iqama: { isha: 17, fajr: 30 }, offsets: { asr: 99 }, jumuah: 7 }));
  assert.equal(s.iqama.isha, 20);
  assert.equal(s.iqama.fajr, 30);
  assert.equal(s.offsets.asr, 0);
  assert.equal(s.jumuah, 0);
});

test("the Adhan screen counts to the mosque's own iqama", () => {
  const cfg = mosqueSettings(JSON.stringify({ iqama: { isha: 15 } }));
  const plan = schedule(riyadh, cfg, thu), isha = time(plan, 'isha');
  const w = adhanWindow(plan, new Date(+isha + 60e3), cfg, isFriday);
  assert.equal(w.k, 'isha');
  assert.equal(+w.iqama, +isha + 15 * MIN);
  assert.equal(adhanWindow(plan, new Date(+isha + 15 * MIN), cfg, isFriday), null, 'the screen ends at the iqama');
  assert.equal(iqamaMinutes(cfg, 'isha', false), 15);
});

test("Friday: no iqama countdown unless the Jumu'ah is set, then that one", () => {
  let cfg = mosqueSettings(null);
  let plan = schedule(riyadh, cfg, fri);
  const dhuhr = time(plan, 'dhuhr');
  let w = adhanWindow(plan, new Date(+dhuhr + MIN), cfg, isFriday);
  assert.equal(w.iqama, null);
  assert.equal(adhanWindow(plan, new Date(+dhuhr + 6 * MIN), cfg, isFriday), null, 'brief screen only');
  cfg = mosqueSettings(JSON.stringify({ jumuah: 30 }));
  w = adhanWindow(plan, new Date(+dhuhr + 6 * MIN), cfg, isFriday);
  assert.equal(+w.iqama, +dhuhr + 30 * MIN);
  // Thursday's Dhuhr still uses the Dhuhr wait.
  plan = schedule(riyadh, cfg, thu);
  assert.equal(+adhanWindow(plan, new Date(+time(plan, 'dhuhr') + MIN), cfg, isFriday).iqama, +time(plan, 'dhuhr') + 20 * MIN);
});

test('a wait of 0: a brief Adhan screen and no countdown', () => {
  const cfg = mosqueSettings(JSON.stringify({ iqama: { maghrib: 0 } }));
  const plan = schedule(riyadh, cfg, thu), maghrib = time(plan, 'maghrib');
  assert.equal(adhanWindow(plan, new Date(+maghrib + MIN), cfg, isFriday).iqama, null);
});

test('Hanafi Asr is later; minutes move only their own time', () => {
  const std = schedule(riyadh, mosqueSettings(null), thu);
  const han = schedule(riyadh, mosqueSettings(JSON.stringify({ asr: 'hanafi' })), thu);
  const later = (time(han, 'asr') - time(std, 'asr')) / MIN;
  assert.ok(later > 30 && later < 90, `Hanafi Asr ${later} min later`);
  const moved = schedule(riyadh, mosqueSettings(JSON.stringify({ offsets: { fajr: 2, isha: -3 } })), thu);
  assert.equal((time(moved, 'fajr') - time(std, 'fajr')) / MIN, 2);
  assert.equal((time(moved, 'isha') - time(std, 'isha')) / MIN, -3);
  assert.equal(+time(moved, 'dhuhr'), +time(std, 'dhuhr'));
  assert.equal((moved.tomorrowFajr - std.tomorrowFajr) / MIN, 2);
});

test('a chosen method replaces the city one', () => {
  const auto = schedule(riyadh, mosqueSettings(null), thu);
  assert.equal(auto.method, 'uaq');
  const mwl = schedule(riyadh, mosqueSettings(JSON.stringify({ method: 'mwl' })), thu);
  assert.equal(mwl.method, 'mwl');
  assert.notEqual(+time(mwl, 'isha'), +time(auto, 'isha'));
  assert.equal(schedule(riyadh, mosqueSettings(JSON.stringify({ method: 'nope' })), thu).method, 'uaq');
});

console.log(`${passed} TV page tests passed`);
