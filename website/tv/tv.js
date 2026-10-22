// Mosque Pro on a TV's own browser (Samsung, LG, or any smart TV): the prayer board, the Adhan moment and a night
// screensaver, worked out in the browser from the same formulas as the app (../prayer.js) on the app's sky
// (../sky.js). Nothing is installed on the TV and nothing is sent anywhere; the city, language and switches are kept
// in this browser only. The TV's remote: OK opens the settings, the arrows move between them, Back closes them.
//
// Written for the older Chromium inside TV browsers (2021 Samsung and LG and newer): no top-level await, no ?. or ??.
import { places } from '../places.js';
import { resolveCity, schedule, nextPrayer, skyT, clock } from '../prayer.js';

const $ = (s) => document.querySelector(s);
const store = {
  get: (k) => { try { return localStorage.getItem(k); } catch (e) { return null; } },
  set: (k, v) => { try { localStorage.setItem(k, v); } catch (e) { /* private window: the defaults stay */ } },
};

const T = {
  ar: {
    prayers: { fajr: 'الفجر', sunrise: 'الشروق', dhuhr: 'الظهر', jumuah: 'الجمعة', asr: 'العصر', maghrib: 'المغرب', isha: 'العشاء' },
    next: 'الصلاة القادمة', adhan: 'حان الآن موعد أذان', iqama: 'الإقامة بعد', ayah: 'آية اليوم', hadith: 'حديث اليوم',
    nightNext: (name, time) => `${name} الساعة ${time}`,
    settings: 'الإعدادات', city: 'المدينة', lang: 'اللغة', langName: 'English', sound: 'صوت الأذان', night: 'شاشة الليل',
    on: 'يعمل', off: 'متوقف', auto: 'تلقائي', close: 'إغلاق',
    hint: 'تظهر شاشة الليل بعد العشاء بساعة ونصف حتى قبل الفجر بنصف ساعة. صوت الأذان يحتاج ضغطة واحدة على زر OK بعد فتح الصفحة.',
    tip: 'اضغط OK للإعدادات', sourceSep: ' · ',
  },
  en: {
    prayers: { fajr: 'Fajr', sunrise: 'Sunrise', dhuhr: 'Dhuhr', jumuah: "Jumu'ah", asr: 'Asr', maghrib: 'Maghrib', isha: 'Isha' },
    next: 'Next prayer', adhan: 'Time for the Adhan of', iqama: 'Iqama in', ayah: 'Verse of the day', hadith: 'Hadith of the day',
    nightNext: (name, time) => `${name} at ${time}`,
    settings: 'Settings', city: 'City', lang: 'Language', langName: 'العربية', sound: 'Adhan sound', night: 'Night screen',
    on: 'On', off: 'Off', auto: 'Automatic', close: 'Close',
    hint: 'The night screen shows from 90 minutes after Isha until 30 minutes before Fajr. The Adhan sound needs one press of OK after the page opens.',
    tip: 'Press OK for settings', sourceSep: ' · ',
  },
};
// Minutes from the Adhan to the iqama (the common ones in Saudi mosques); the Adhan screen stays up until then.
const IQAMA = { fajr: 25, dhuhr: 20, asr: 20, maghrib: 10, isha: 20 };
const JUMUAH_SCREEN = 5; // On Friday the khutbah follows, so the Adhan screen shows only briefly.
const MIN = 60e3;

let lang = store.get('mp-tv-lang') || ((navigator.languages || [navigator.language]).some((l) => /^ar/i.test(l)) ? 'ar' : 'en');
let sound = store.get('mp-tv-sound') === '1';
let nightOn = store.get('mp-tv-night') !== '0';
let city = null, plan = null, planDay = '', daily = null, played = '', unlocked = false, mode = '';

const t = () => T[lang];
const cityName = () => (lang === 'ar' ? city.ar : city.en);
const at = (d) => clock(d, city.tz, lang);
const ymd = (d) => new Intl.DateTimeFormat('en-CA', { timeZone: city.tz, year: 'numeric', month: '2-digit', day: '2-digit' }).format(d);
const isFriday = (d) => new Intl.DateTimeFormat('en-US', { timeZone: city.tz, weekday: 'short' }).format(d) === 'Fri';
const name = (k, d) => t().prayers[k === 'dhuhr' && isFriday(d) ? 'jumuah' : k];

function pad(n) { return n < 10 ? '0' + n : '' + n; }
function countdown(ms) {
  const s = Math.max(0, Math.floor(ms / 1000));
  return `${Math.floor(s / 3600)}:${pad(Math.floor(s / 60) % 60)}:${pad(s % 60)}`;
}

// The verse and hadith of the day: the same pick as the app (days since the epoch, round the list), for the city's date.
function dailyPick(now) {
  if (!daily) return null;
  const [y, m, d] = ymd(now).split('-').map(Number), [ey, em, ed] = daily.epoch.split('-').map(Number);
  const days = Math.round((Date.UTC(y, m - 1, d) - Date.UTC(ey, em - 1, ed)) / 864e5);
  const mod = (n, c) => ((n % c) + c) % c;
  return { ayah: daily.ayat[mod(days, daily.ayat.length)], hadith: daily.hadith[mod(days, daily.hadith.length)] };
}

// Which screen: the Adhan from its time until the iqama, the night screen late at night, else the board.
function adhanNow(now) {
  for (const [k, v] of plan.today) {
    if (k === 'sunrise') continue;
    const friday = k === 'dhuhr' && isFriday(now);
    const end = +v + (friday ? JUMUAH_SCREEN : IQAMA[k]) * MIN;
    if (now >= v && now < end) return { k, at: v, iqama: friday ? null : new Date(+v + IQAMA[k] * MIN) };
  }
  return null;
}
function isNight(now) {
  if (!nightOn) return false;
  const isha = plan.today.find(([k]) => k === 'isha')[1], fajr = plan.today.find(([k]) => k === 'fajr')[1];
  const late = (from, to) => now >= +from + 90 * MIN && now < +to - 30 * MIN;
  return late(isha, plan.tomorrowFajr) || late(plan.yesterdayIsha, fajr);
}

function show(next) {
  if (mode === next) return;
  mode = next;
  ['board', 'adhan', 'night'].forEach((id) => { $('#' + id).hidden = id !== next; });
  $('.sky').style.visibility = next === 'board' ? 'visible' : 'hidden';
}

function playAdhan(key) {
  if (!sound || played === key) return;
  played = key;
  const a = $('#adhan-audio');
  a.currentTime = 0;
  const p = a.play();
  if (p && p.catch) p.catch(() => { if (!unlocked) tip(t().hint); });
}

let lastSky = -1, lastShift = 0;
function tick() {
  const now = new Date();
  if (ymd(now) !== planDay) { plan = schedule(city); planDay = ymd(now); }
  const tx = t(), adhan = adhanNow(now);
  if (adhan) {
    show('adhan');
    $('#adhan-label').textContent = tx.adhan;
    $('#adhan-name').textContent = name(adhan.k, now);
    $('.iqama').hidden = !adhan.iqama;
    if (adhan.iqama) { $('#iqama-label').textContent = tx.iqama; $('#iqama-in').textContent = countdown(adhan.iqama - now).replace(/^0:/, ''); }
    playAdhan(planDay + adhan.k);
    return;
  }
  const next = nextPrayer(plan, now);
  if (isNight(now)) {
    show('night');
    $('#night-clock').textContent = at(now);
    $('#night-next').textContent = tx.nightNext(name(next[0], next[1]), at(next[1]));
    // Move a little every minute so nothing stays lit in one place all night.
    if (now - lastShift > MIN) {
      lastShift = +now;
      const box = $('#night-box');
      box.style.top = (10 + Math.random() * 55) + 'vh';
      box.style.left = (5 + Math.random() * 45) + 'vw';
    }
    return;
  }
  show('board');
  $('#clock').textContent = at(now);
  $('#next-name').textContent = name(next[0], next[1]);
  $('#next-at').textContent = at(next[1]);
  $('#countdown').textContent = countdown(next[1] - now);
  const current = plan.today.filter(([k, v]) => k !== 'sunrise' && v <= now).pop();
  const nowKey = current ? current[0] : 'isha';
  if (now.getSeconds() === 0 || !$('#times').children.length) renderTimes(now, next, nowKey);
  // The verse and the hadith take turns, a minute each.
  const pick = dailyPick(now);
  $('#daily').hidden = !pick;
  if (pick) {
    const ayahTurn = Math.floor(now / MIN) % 2 === 0;
    $('#daily-label').textContent = ayahTurn ? tx.ayah : tx.hadith;
    if (ayahTurn) {
      $('#daily-ar').textContent = pick.ayah.ar;
      $('#daily-tr').textContent = lang === 'ar' ? '' : pick.ayah.en;
      $('#daily-ref').textContent = (lang === 'ar' ? pick.ayah.surah.ar : pick.ayah.surah.translit) + ' · ' + pick.ayah.ref;
    } else {
      $('#daily-ar').textContent = '«' + pick.hadith.ar.text + '»';
      $('#daily-tr').textContent = lang === 'ar' ? '' : pick.hadith.en;
      $('#daily-ref').textContent = pick.hadith.ar.grade + tx.sourceSep + pick.hadith.ar.source + tx.sourceSep + 'HadeethEnc.com';
    }
  }
  const st = skyT(plan, now);
  if (Math.abs(st - lastSky) > 0.001 && typeof drawSky === 'function') {
    const c = $('.sky');
    drawSky(c.getContext('2d'), c.width, c.height, st, { horizon: 0.86, mosque: 0.12, mosqueX: lang === 'ar' ? 0.2 : 0.8 });
    lastSky = st;
  }
  // A few pixels' drift every three minutes, against burn-in on screens left on all day.
  if (now - lastShift > 3 * MIN) {
    lastShift = +now;
    $('#board').style.transform = `translate(${(Math.random() - 0.5) * 0.8}vw, ${(Math.random() - 0.5) * 0.8}vh)`;
  }
}

function renderTimes(now, next, nowKey) {
  $('#times').innerHTML = '';
  plan.today.forEach(([k, v]) => {
    const li = document.createElement('li');
    if (k === 'sunrise') li.className = 'is-sunrise';
    if (k === next[0] && +next[1] === +v) li.classList.add('is-next');
    if (k === nowKey && v <= now) li.classList.add('is-now');
    const n = document.createElement('span'), b = document.createElement('b');
    n.textContent = name(k, now); b.textContent = at(v);
    li.append(n, b);
    $('#times').append(li);
  });
}

function render() {
  const tx = t(), now = new Date();
  document.documentElement.lang = lang;
  document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
  $('#city').textContent = cityName();
  $('#date').textContent = new Intl.DateTimeFormat(lang === 'ar' ? 'ar-SA-u-ca-gregory-nu-latn' : 'en-GB', { timeZone: city.tz, weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).format(now);
  try {
    $('#hijri').textContent = new Intl.DateTimeFormat((lang === 'ar' ? 'ar-SA' : 'en-GB') + '-u-ca-islamic-umalqura-nu-latn', { timeZone: city.tz, day: 'numeric', month: 'long', year: 'numeric' }).format(now);
  } catch (e) { $('#hijri').textContent = ''; }
  $('#next-label').textContent = tx.next;
  $('#s-title').textContent = tx.settings;
  $('#s-city-l').textContent = tx.city;
  $('#s-city').textContent = cityName();
  $('#s-lang-l').textContent = tx.lang;
  $('#s-lang').textContent = tx.langName;
  $('#s-sound-l').textContent = tx.sound;
  $('#s-sound').textContent = sound ? tx.on : tx.off;
  $('#s-night-l').textContent = tx.night;
  $('#s-night').textContent = nightOn ? tx.auto : tx.off;
  $('#s-hint').textContent = tx.hint;
  $('#s-close').textContent = tx.close;
  plan = schedule(city); planDay = ymd(now);
  $('#times').innerHTML = '';
  lastSky = -1; mode = '';
  tick();
}

function sizeSky() {
  const c = $('.sky'), r = Math.min(window.devicePixelRatio || 1, 1.5);
  c.width = Math.round(innerWidth * r); c.height = Math.round(innerHeight * r);
  lastSky = -1;
}

let tipTimer = 0;
function tip(text) {
  const el = $('#tip');
  el.textContent = text; el.classList.remove('gone');
  clearTimeout(tipTimer);
  tipTimer = setTimeout(() => el.classList.add('gone'), 8000);
}

// Settings, by remote: OK opens them, the arrows walk the buttons, OK presses one, Back closes.
const dlg = $('#settings');
const buttons = () => Array.from(dlg.querySelectorAll('button'));
function openSettings() { if (!dlg.open) { dlg.showModal(); $('#s-close').focus(); } }
function closeSettings() { if (dlg.open) dlg.close(); }
function moveCity(step) {
  const i = places.findIndex((p) => p[0] === city.en);
  const p = places[((i < 0 ? 0 : i + step) % places.length + places.length) % places.length];
  city = { en: p[0], ar: p[1], lat: p[2], lon: p[3], tz: p[4] };
  store.set('mp-tv-city', p[0]);
  render();
}
$('#s-city-prev').addEventListener('click', () => moveCity(-1));
$('#s-city-next').addEventListener('click', () => moveCity(1));
$('#s-lang').addEventListener('click', () => { lang = lang === 'ar' ? 'en' : 'ar'; store.set('mp-tv-lang', lang); render(); });
$('#s-sound').addEventListener('click', () => { sound = !sound; store.set('mp-tv-sound', sound ? '1' : '0'); unlockAudio(); render(); });
$('#s-night').addEventListener('click', () => { nightOn = !nightOn; store.set('mp-tv-night', nightOn ? '1' : '0'); render(); });
$('#s-close').addEventListener('click', closeSettings);

// A TV browser plays sound only after a key press on the page: the first OK primes the Adhan, silently.
function unlockAudio() {
  if (unlocked || !sound) return;
  const a = $('#adhan-audio');
  a.muted = true;
  const p = a.play();
  const done = () => { a.pause(); a.muted = false; a.currentTime = 0; unlocked = true; };
  if (p && p.then) p.then(done, () => { a.muted = false; }); else done();
}

const BACK = { Escape: 1, Backspace: 1, GoBack: 1, BrowserBack: 1 };
addEventListener('keydown', (e) => {
  unlockAudio();
  if (!dlg.open) {
    if (e.key === 'Enter' || e.keyCode === 13) { e.preventDefault(); openSettings(); }
    return;
  }
  if (BACK[e.key] || e.keyCode === 10009 || e.keyCode === 461) { e.preventDefault(); closeSettings(); return; }
  const list = buttons(), i = list.indexOf(document.activeElement);
  const step = { ArrowDown: 1, ArrowRight: lang === 'ar' ? -1 : 1, ArrowUp: -1, ArrowLeft: lang === 'ar' ? 1 : -1 }[e.key];
  if (step) { e.preventDefault(); list[(i + step + list.length) % list.length].focus(); }
});
addEventListener('click', (e) => { unlockAudio(); if (!dlg.open && !dlg.contains(e.target)) openSettings(); });
addEventListener('resize', () => { sizeSky(); tick(); });

// Keep the screen on where the browser allows it.
function keepAwake() { try { if (navigator.wakeLock) navigator.wakeLock.request('screen').catch(() => {}); } catch (e) { /* not offered */ } }
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') keepAwake(); });

resolveCity(places, '../assets/zones.json', store.get('mp-tv-city')).then((c) => {
  city = c;
  sizeSky();
  render();
  tip(t().tip);
  keepAwake();
  setInterval(tick, 1000);
  fetch('daily.json').then((r) => r.json()).then((d) => { daily = d; tick(); }).catch(() => {});
});
