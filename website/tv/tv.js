// Mosque Pro on a TV (a TV's own browser, or the LG app that tools/webos/build.py packs from this folder): the prayer
// board, the Adhan moment and a night screen, worked out on the TV from the same formulas as the app (../prayer.js).
// Nothing is sent anywhere; the city, language and switches are kept on the TV only. The remote: OK opens the
// settings, the arrows move between their four tiles, OK changes one, Back closes them.
//
// Written for the older Chromium inside TVs: no top-level await, no ?. or ??; the LG build turns the modules into one
// plain script, so they must stay import/export only.
import { places } from '../places.js';
import { resolveCity, schedule, nextPrayer, qibla, clock } from '../prayer.js';

const $ = (s) => document.querySelector(s);
const store = {
  get: (k) => { try { return localStorage.getItem(k); } catch (e) { return null; } },
  set: (k, v) => { try { localStorage.setItem(k, v); } catch (e) { /* private window: the defaults stay */ } },
};

const T = {
  ar: {
    prayers: { fajr: 'الفجر', sunrise: 'الشروق', dhuhr: 'الظهر', jumuah: 'الجمعة', asr: 'العصر', maghrib: 'المغرب', isha: 'العشاء' },
    next: 'الصلاة القادمة', remain: 'متبقية', adhan: 'حان الآن موعد أذان', iqama: 'الإقامة بعد', ayah: 'آية اليوم', hadith: 'حديث اليوم',
    iqamaOf: (n) => 'إقامة ' + n, qibla: 'القبلة', qiblaDeg: (d) => d + '° من الشمال', net: 'الشبكة', netClean: 'نظيفة · بلا إعلانات',
    nightNext: (name, time, left) => `${name} ${time} · بعد ${left}`, hours: (h, m) => (h ? h + ' س و ' : '') + m + ' د',
    adhanHint: 'الأذان يعمل · اضغط OK لإيقافه',
    settings: 'الإعدادات', keys: 'الأسهم للتنقّل · OK للتغيير · رجوع للإغلاق',
    city: 'المدينة', lang: 'اللغة', langName: 'العربية', sound: 'صوت الأذان', night: 'شاشة الليل',
    on: 'يعمل', off: 'متوقف', auto: 'تلقائي',
    hint: 'تُحفظ اختياراتك في هذا التلفاز فقط. شاشة الليل من بعد العشاء بساعة ونصف حتى قبل الفجر بنصف ساعة.',
    tip: 'اضغط OK للإعدادات', sourceSep: ' · ',
  },
  en: {
    prayers: { fajr: 'Fajr', sunrise: 'Sunrise', dhuhr: 'Dhuhr', jumuah: "Jumu'ah", asr: 'Asr', maghrib: 'Maghrib', isha: 'Isha' },
    next: 'Next prayer', remain: 'to go', adhan: 'Time for the Adhan of', iqama: 'Iqama in', ayah: 'Verse of the day', hadith: 'Hadith of the day',
    iqamaOf: (n) => n + ' iqama', qibla: 'Qibla', qiblaDeg: (d) => d + '° from north', net: 'Network', netClean: 'Clean · no ads',
    nightNext: (name, time, left) => `${name} ${time} · in ${left}`, hours: (h, m) => (h ? h + 'h ' : '') + m + 'm',
    adhanHint: 'Adhan playing · press OK to stop',
    settings: 'Settings', keys: 'Arrows to move · OK to change · Back to close',
    city: 'City', lang: 'Language', langName: 'English', sound: 'Adhan sound', night: 'Night screen',
    on: 'On', off: 'Off', auto: 'Automatic',
    hint: 'Your choices stay on this TV only. The night screen shows from 90 minutes after Isha until 30 minutes before Fajr.',
    tip: 'Press OK for settings', sourceSep: ' · ',
  },
};
// Minutes from the Adhan to the iqama (the common ones in Saudi mosques); the Adhan screen stays up until then.
const IQAMA = { fajr: 25, dhuhr: 20, asr: 20, maghrib: 10, isha: 20 };
const JUMUAH_SCREEN = 5; // On Friday the khutbah follows, so the Adhan screen shows only briefly.
const MIN = 60e3;
const webOS = typeof window.PalmSystem !== 'undefined';

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
const side = () => (lang === 'ar' ? 'right' : 'left');

function pad(n) { return n < 10 ? '0' + n : '' + n; }
function countdown(ms) {
  const s = Math.max(0, Math.floor(ms / 1000)), h = Math.floor(s / 3600);
  return (h ? h + ':' : '') + pad(Math.floor(s / 60) % 60) + ':' + pad(s % 60);
}
// A file next to this page, by XHR: it works over the web and from an installed TV app's own files alike.
function getJSON(url) {
  return new Promise((ok, fail) => {
    const x = new XMLHttpRequest();
    x.open('GET', url);
    x.onload = () => { try { ok(JSON.parse(x.responseText)); } catch (e) { fail(e); } };
    x.onerror = fail;
    x.send();
  });
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
function nightSpan(now) {
  const isha = plan.today.find(([k]) => k === 'isha')[1], fajr = plan.today.find(([k]) => k === 'fajr')[1];
  if (now >= +isha + 90 * MIN && now < +plan.tomorrowFajr - 30 * MIN) return [isha, plan.tomorrowFajr];
  if (now >= +plan.yesterdayIsha + 90 * MIN && now < +fajr - 30 * MIN) return [plan.yesterdayIsha, fajr];
  return null;
}

function show(next) {
  if (mode === next) return;
  mode = next;
  ['board', 'adhan', 'night'].forEach((id) => { $('#' + id).hidden = id !== next; });
}

function playAdhan(key) {
  if (!sound || played === key) return;
  played = key;
  const a = $('#adhan-audio');
  a.currentTime = 0;
  const p = a.play();
  if (p && p.catch) p.catch(() => {});
}
function stopAdhan() { const a = $('#adhan-audio'); if (!a.paused) { a.pause(); return true; } return false; }

let lastShift = 0;
function tick() {
  const now = new Date();
  if (ymd(now) !== planDay) { plan = schedule(city); planDay = ymd(now); }
  const tx = t(), adhan = adhanNow(now);
  if (adhan) {
    show('adhan');
    $('#adhan-label').textContent = tx.adhan;
    $('#adhan-name').textContent = name(adhan.k, now);
    $('#ring').hidden = !adhan.iqama;
    if (adhan.iqama) {
      const total = IQAMA[adhan.k] * MIN, left = adhan.iqama - now;
      $('#iqama-label').textContent = tx.iqama;
      $('#iqama-in').textContent = countdown(left);
      $('#ring-fg').style.strokeDashoffset = String(440 * (1 - left / total));
    }
    $('#adhan-foot').textContent = cityName() + ' · ' + at(now);
    $('#adhan-hint').textContent = sound && !$('#adhan-audio').paused ? tx.adhanHint : '';
    playAdhan(planDay + adhan.k);
    return;
  }
  const next = nextPrayer(plan, now);
  const night = nightOn && nightSpan(now);
  if (night) {
    show('night');
    const left = Math.max(0, Math.round((next[1] - now) / MIN));
    const nc = at(now).split(' ');
    $('#night-clock').textContent = nc[0];
    $('#night-ampm').textContent = nc.slice(1).join(' ');
    $('#night-next').textContent = tx.nightNext(name(next[0], next[1]), at(next[1]), tx.hours(Math.floor(left / 60), left % 60));
    $('#night-fill').style.width = Math.min(100, 100 * (now - night[0]) / (night[1] - night[0])).toFixed(1) + '%';
    // Move a little every minute so nothing stays lit in one place all night.
    if (now - lastShift > MIN) {
      lastShift = +now;
      const box = $('#night-box');
      box.style.top = (12 + Math.random() * 40) + 'vh';
      box.style.left = (6 + Math.random() * 40) + 'vw';
    }
    return;
  }
  show('board');
  $('#clock').textContent = at(now);
  $('#next-name').textContent = name(next[0], next[1]);
  $('#next-at').textContent = at(next[1]);
  $('#countdown').textContent = countdown(next[1] - now);
  if (IQAMA[next[0]] && !(next[0] === 'dhuhr' && isFriday(next[1]))) {
    $('#chip-iqama').hidden = false;
    $('#iqama-l').textContent = tx.iqamaOf(name(next[0], next[1]));
    $('#iqama-at').textContent = at(new Date(+next[1] + IQAMA[next[0]] * MIN));
  } else $('#chip-iqama').hidden = true;
  renderLine(now, next);
  renderDaily(now);
  // A few pixels' drift every three minutes, against burn-in on screens left on all day.
  if (now - lastShift > 3 * MIN) {
    lastShift = +now;
    $('#board').style.transform = `translate(${(Math.random() - 0.5) * 0.8}vw, ${(Math.random() - 0.5) * 0.8}vh)`;
  }
}

// The day as a line from Fajr to Isha: the passed times in gold, the next one ringed, the sun where now is.
let lineKey = '';
function renderLine(now, next) {
  const fajr = +plan.today[0][1], isha = +plan.today[5][1], span = isha - fajr;
  const pct = (v) => Math.max(0, Math.min(100, 100 * (v - fajr) / span));
  const key = lang + planDay + next[0] + Math.floor(now / MIN);
  if (key !== lineKey) {
    lineKey = key;
    const marks = $('#marks');
    marks.innerHTML = '';
    plan.today.forEach(([k, v]) => {
      const el = document.createElement('div');
      el.className = 'mark' + (k === 'sunrise' ? ' sunrise' : '') + (k === next[0] && +v === +next[1] ? ' next' : v <= now ? ' past' : '');
      el.style[side()] = pct(+v) + '%';
      const n = document.createElement('span'), i = document.createElement('i'), b = document.createElement('b');
      n.textContent = name(k, now); b.textContent = at(v);
      el.appendChild(n); el.appendChild(i); el.appendChild(b);
      marks.appendChild(el);
    });
  }
  const inDay = now >= fajr && now <= isha;
  const p = inDay ? pct(+now) : now > isha ? 100 : 0;
  $('#rail-done').style.width = p + '%';
  const sun = $('#sun');
  sun.hidden = !inDay;
  sun.style.left = sun.style.right = '';
  sun.style[side()] = p + '%';
}

// The verse and the hadith take turns, a minute each; a long one gets a smaller size so it still fits.
function renderDaily(now) {
  const pick = dailyPick(now), tx = t();
  $('#daily').hidden = !pick;
  if (!pick) return;
  const ayahTurn = Math.floor(now / MIN) % 2 === 0;
  let ar, tr, ref;
  if (ayahTurn) {
    ar = pick.ayah.ar; tr = pick.ayah.en;
    ref = (lang === 'ar' ? 'سورة ' + pick.ayah.surah.ar : pick.ayah.surah.translit) + ' · ' + pick.ayah.ref;
  } else {
    ar = '«' + pick.hadith.ar.text + '»'; tr = pick.hadith.en;
    ref = pick.hadith.ar.grade + tx.sourceSep + pick.hadith.ar.source + tx.sourceSep + 'HadeethEnc.com';
  }
  $('#daily-label').textContent = ayahTurn ? tx.ayah : tx.hadith;
  const el = $('#daily-ar');
  if (el.textContent !== ar) {
    el.textContent = ar;
    el.className = 'daily-ar' + (ar.length > 260 ? ' longer' : ar.length > 140 ? ' long' : '');
  }
  $('#daily-tr').textContent = lang === 'ar' ? '' : tr;
  $('#daily-ref').textContent = ref;
}

function render() {
  const tx = t(), now = new Date();
  document.documentElement.lang = lang;
  document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
  $('#city').textContent = cityName();
  $('#date').textContent = new Intl.DateTimeFormat(lang === 'ar' ? 'ar-SA-u-ca-gregory-nu-latn' : 'en-GB', { timeZone: city.tz, weekday: 'long', day: 'numeric', month: 'long' }).format(now);
  try {
    $('#hijri').textContent = new Intl.DateTimeFormat((lang === 'ar' ? 'ar-SA' : 'en-GB') + '-u-ca-islamic-umalqura-nu-latn', { timeZone: city.tz, day: 'numeric', month: 'long', year: 'numeric' }).format(now);
  } catch (e) { $('#hijri').textContent = ''; }
  $('#next-label').textContent = tx.next;
  $('#remain-l').textContent = tx.remain;
  $('#qibla-l').textContent = tx.qibla;
  $('#qibla').textContent = tx.qiblaDeg(qibla(city).deg);
  $('#net-l').textContent = tx.net;
  $('#net').textContent = tx.netClean;
  $('#s-title').textContent = tx.settings;
  $('#s-keys').textContent = tx.keys;
  $('#s-city-l').textContent = tx.city;
  $('#s-city-v').textContent = cityName();
  $('#s-lang-l').textContent = tx.lang;
  $('#s-lang-v').textContent = tx.langName;
  $('#s-sound-l').textContent = tx.sound;
  $('#s-sound-v').textContent = sound ? tx.on : tx.off;
  $('#s-night-l').textContent = tx.night;
  $('#s-night-v').textContent = nightOn ? tx.auto : tx.off;
  $('#s-hint').textContent = tx.hint;
  plan = schedule(city); planDay = ymd(now);
  lineKey = ''; mode = '';
  tick();
}

// "Clean · no ads" shows only when it's true: an ad server doesn't answer while an ordinary site does, which is what
// a blocking DNS (AdGuard, the router's or the TV's) does.
function checkNetwork() {
  if (typeof fetch !== 'function') return;
  const reach = (u) => fetch(u, { mode: 'no-cors', cache: 'no-store' }).then(() => true, () => false);
  Promise.all([reach('https://www.google.com/generate_204'), reach('https://googleads.g.doubleclick.net/pagead/id')])
    .then(([web, ads]) => { $('#chip-net').hidden = !(web && !ads); });
}

let tipTimer = 0;
function tip(text) {
  const el = $('#tip');
  el.textContent = text; el.classList.remove('gone');
  clearTimeout(tipTimer);
  tipTimer = setTimeout(() => el.classList.add('gone'), 8000);
}

// Settings, by remote: OK opens them, the arrows walk the 2×2 tiles, OK changes one, Back closes.
const dlg = $('#settings');
const tiles = () => Array.from(dlg.querySelectorAll('.tile'));
function openSettings() { if (!dlg.open) { dlg.showModal(); tiles()[0].focus(); } }
function closeSettings() { if (dlg.open) dlg.close(); }
function moveCity(step) {
  const i = places.findIndex((p) => p[0] === city.en);
  const p = places[((i < 0 ? 0 : i + step) % places.length + places.length) % places.length];
  city = { en: p[0], ar: p[1], lat: p[2], lon: p[3], tz: p[4] };
  store.set('mp-tv-city', p[0]);
  render();
}
$('#s-city').addEventListener('click', () => moveCity(1));
$('#s-lang').addEventListener('click', () => { lang = lang === 'ar' ? 'en' : 'ar'; store.set('mp-tv-lang', lang); render(); });
$('#s-sound').addEventListener('click', () => { sound = !sound; store.set('mp-tv-sound', sound ? '1' : '0'); unlockAudio(); render(); });
$('#s-night').addEventListener('click', () => { nightOn = !nightOn; store.set('mp-tv-night', nightOn ? '1' : '0'); render(); });

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
  const back = BACK[e.key] || e.keyCode === 10009 || e.keyCode === 461;
  if (!dlg.open) {
    if (e.key === 'Enter' || e.keyCode === 13) {
      e.preventDefault();
      if (!stopAdhan()) { unlockAudio(); openSettings(); }
    } else if (back && webOS) { e.preventDefault(); window.close(); }
    return;
  }
  if (back) { e.preventDefault(); closeSettings(); return; }
  const list = tiles(), i = list.indexOf(document.activeElement);
  const rtl = lang === 'ar';
  const step = { ArrowDown: 2, ArrowUp: -2, ArrowRight: rtl ? -1 : 1, ArrowLeft: rtl ? 1 : -1 }[e.key];
  if (step) { e.preventDefault(); list[(Math.max(i, 0) + step + 4) % 4].focus(); }
});
addEventListener('click', (e) => { unlockAudio(); if (!dlg.open && !dlg.contains(e.target)) openSettings(); });
addEventListener('resize', () => { lineKey = ''; tick(); });

// Keep the screen on: the browser's wake lock where there is one; on an LG TV, the app answers the TV's screensaver
// request with "not now", as LG's video apps do.
function keepAwake() { try { if (navigator.wakeLock) navigator.wakeLock.request('screen').catch(() => {}); } catch (e) { /* not offered */ } }
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') keepAwake(); });
function holdScreensaver() {
  if (!webOS || typeof window.PalmServiceBridge === 'undefined') return;
  const svc = 'luna://com.webos.service.tvpower/power/';
  const id = 'sa.zood.mosquepro.tv';
  const reg = new window.PalmServiceBridge();
  reg.onservicecallback = (msg) => {
    let r = {};
    try { r = JSON.parse(msg); } catch (e) { return; }
    if (r.state === 'Active' && r.timestamp) {
      const ans = new window.PalmServiceBridge();
      ans.call(svc + 'responseScreenSaverRequest', JSON.stringify({ clientName: id, ack: false, timestamp: r.timestamp }));
    }
  };
  reg.call(svc + 'registerScreenSaverRequest', JSON.stringify({ subscribe: true, clientName: id }));
  window.__mpSaver = reg; // keep the subscription alive
}

resolveCity(places, '../assets/zones.json', store.get('mp-tv-city')).then((c) => {
  city = c;
  render();
  tip(t().tip);
  keepAwake();
  holdScreensaver();
  checkNetwork();
  setInterval(tick, 1000);
  setInterval(checkNetwork, 30 * MIN);
  getJSON('daily.json').then((d) => { daily = d; tick(); }).catch(() => {});
});
