// Mosque Pro on a TV: a home screen (in a TV's own browser, or the LG app tools/webos/build.py packs from this folder).
// On top the prayer board; below it, rows the remote walks through: the TV's apps, today (the weather, the six times,
// the Qibla, the network), and the settings. At the Adhan the Adhan screen counts to the iqama; late at night a dim
// clock moves about the screen. Any key brings the home screen back for a few minutes. The times come from the same
// formulas as the app (../prayer.js); the choices stay on the TV. The weather is Open-Meteo's (no key, no account).
//
// Written for the older Chromium inside TVs: no top-level await, no ?. or ??; the LG build turns the modules into one
// plain script, so they must stay import/export only. launcher.js (a plain script) gives window.TVApps.
import { places } from '../places.js';
import { resolveCity, schedule, nextPrayer, qibla, clock } from '../prayer.js';

const $ = (s) => document.querySelector(s);
const store = {
  get: (k) => { try { return localStorage.getItem(k); } catch (e) { return null; } },
  set: (k, v) => { try { if (v === null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch (e) { /* private window */ } },
};
const apps = window.TVApps;

const T = {
  ar: {
    prayers: { fajr: 'الفجر', sunrise: 'الشروق', dhuhr: 'الظهر', jumuah: 'الجمعة', asr: 'العصر', maghrib: 'المغرب', isha: 'العشاء' },
    next: 'الصلاة القادمة', remain: 'متبقية', adhan: 'حان الآن موعد أذان', iqama: 'الإقامة بعد', ayah: 'آية اليوم', hadith: 'حديث اليوم',
    iqamaOf: (n) => 'إقامة ' + n, net: 'الشبكة', netClean: 'نظيفة · بلا إعلانات', netAds: 'الإعلانات غير محجوبة',
    netHow: 'لحجبها: إعدادات التلفاز ← الشبكة ← DNS ‏94.140.14.14', netOk: 'تُحجب الإعلانات والمتتبعات على هذه الشبكة',
    nightNext: (name, time, left) => `${name} ${time} · بعد ${left}`, hours: (h, m) => (h ? h + ' س و ' : '') + m + ' د',
    adhanHint: 'الأذان يعمل · اضغط OK لإيقافه',
    apps: 'تطبيقاتك', today: 'اليوم', settings: 'الإعدادات', tvSettings: 'إعدادات التلفاز', open: 'فتح',
    weather: 'الطقس', hiLo: (h, l) => `العظمى ${h}° · الصغرى ${l}°`, times: 'مواقيت اليوم',
    qibla: 'القبلة', fromNorth: 'من الشمال', toMakkah: (km) => km.toLocaleString('ar-SA-u-nu-latn') + ' كم إلى مكة المكرمة',
    city: 'المدينة', lang: 'اللغة', langName: 'العربية', sound: 'صوت الأذان', night: 'شاشة الليل',
    on: 'يعمل', off: 'متوقف', auto: 'تلقائي', autoCity: 'تلقائي (حسب التلفاز)', saudi: 'المملكة العربية السعودية', world: 'مدن أخرى',
    pickCity: 'اختر المدينة', pickKeys: '▲ ▼ للتنقّل · OK للاختيار · رجوع للإلغاء',
    hintApps: '◀ ▶ للتنقّل · OK للفتح · ▼ للمزيد', hintRows: '▲ ▼ بين الأقسام · ◀ ▶ داخلها · رجوع للأعلى', hintPrefs: 'OK للتغيير · رجوع للأعلى',
    wx: { clear: 'صافٍ', partly: 'غائم جزئيًا', cloudy: 'غائم', fog: 'ضباب', drizzle: 'رذاذ', rain: 'مطر', snow: 'ثلج', storm: 'عاصفة رعدية' },
    day: (d) => new Intl.DateTimeFormat('ar-SA-u-nu-latn', { weekday: 'short', timeZone: 'UTC' }).format(d), sourceSep: ' · ',
  },
  en: {
    prayers: { fajr: 'Fajr', sunrise: 'Sunrise', dhuhr: 'Dhuhr', jumuah: "Jumu'ah", asr: 'Asr', maghrib: 'Maghrib', isha: 'Isha' },
    next: 'Next prayer', remain: 'to go', adhan: 'Time for the Adhan of', iqama: 'Iqama in', ayah: 'Verse of the day', hadith: 'Hadith of the day',
    iqamaOf: (n) => n + ' iqama', net: 'Network', netClean: 'Clean · no ads', netAds: 'Ads not blocked',
    netHow: 'To block them: TV settings → Network → DNS 94.140.14.14', netOk: 'Ads and trackers are blocked on this network',
    nightNext: (name, time, left) => `${name} ${time} · in ${left}`, hours: (h, m) => (h ? h + 'h ' : '') + m + 'm',
    adhanHint: 'Adhan playing · press OK to stop',
    apps: 'Your apps', today: 'Today', settings: 'Settings', tvSettings: 'TV settings', open: 'Open',
    weather: 'Weather', hiLo: (h, l) => `High ${h}° · Low ${l}°`, times: "Today's times",
    qibla: 'Qibla', fromNorth: 'from north', toMakkah: (km) => km.toLocaleString('en-US') + ' km to Makkah',
    city: 'City', lang: 'Language', langName: 'English', sound: 'Adhan sound', night: 'Night screen',
    on: 'On', off: 'Off', auto: 'Automatic', autoCity: 'Automatic (from the TV)', saudi: 'Saudi Arabia', world: 'Other cities',
    pickCity: 'Choose the city', pickKeys: '▲ ▼ to move · OK to choose · Back to cancel',
    hintApps: '◀ ▶ to move · OK to open · ▼ for more', hintRows: '▲ ▼ between rows · ◀ ▶ within · Back to the top', hintPrefs: 'OK to change · Back to the top',
    wx: { clear: 'Clear', partly: 'Partly cloudy', cloudy: 'Cloudy', fog: 'Fog', drizzle: 'Drizzle', rain: 'Rain', snow: 'Snow', storm: 'Thunderstorm' },
    day: (d) => new Intl.DateTimeFormat('en-GB', { weekday: 'short', timeZone: 'UTC' }).format(d), sourceSep: ' · ',
  },
};
// Minutes from the Adhan to the iqama (the common ones in Saudi mosques); the Adhan screen stays up until then.
const IQAMA = { fajr: 25, dhuhr: 20, asr: 20, maghrib: 10, isha: 20 };
const JUMUAH_SCREEN = 5; // On Friday the khutbah follows, so the Adhan screen shows only briefly.
const MIN = 60e3;
const WAKE = 3 * MIN; // a key press on the Adhan or night screen shows the home screen this long

// More Saudi cities than the site's globe names, so the TV's list has the Kingdom's cities first.
const SAUDI = [
  ['Riyadh', 'الرياض', 24.7136, 46.6753], ['Makkah', 'مكة المكرمة', 21.4225, 39.8262], ['Madinah', 'المدينة المنورة', 24.4686, 39.6142],
  ['Jeddah', 'جدة', 21.5433, 39.1728], ['Dammam', 'الدمام', 26.4207, 50.0888], ['Khobar', 'الخبر', 26.2172, 50.1971],
  ['Dhahran', 'الظهران', 26.2361, 50.0393], ['Taif', 'الطائف', 21.2703, 40.4158], ['Tabuk', 'تبوك', 28.3835, 36.5662],
  ['Buraidah', 'بريدة', 26.326, 43.975], ['Unaizah', 'عنيزة', 26.084, 43.994], ['Abha', 'أبها', 18.2164, 42.5053],
  ['Khamis Mushait', 'خميس مشيط', 18.3, 42.73], ['Hail', 'حائل', 27.5114, 41.7208], ['Jazan', 'جازان', 16.8892, 42.5511],
  ['Najran', 'نجران', 17.5656, 44.2289], ['Al-Ahsa', 'الأحساء', 25.38, 49.588], ['Qatif', 'القطيف', 26.556, 50.008],
  ['Jubail', 'الجبيل', 27.0174, 49.6225], ['Yanbu', 'ينبع', 24.089, 38.0637], ['Al Kharj', 'الخرج', 24.1556, 47.312],
  ['Al Bahah', 'الباحة', 20.0129, 41.4677], ['Sakaka', 'سكاكا', 29.9697, 40.2064], ['Arar', 'عرعر', 30.9753, 41.0381],
  ['Hafar Al-Batin', 'حفر الباطن', 28.4328, 45.9708], ['Al Majmaah', 'المجمعة', 25.9039, 45.3456], ['Rabigh', 'رابغ', 22.7986, 39.0349],
  ['Al Qurayyat', 'القريات', 31.3318, 37.3428],
].map((p) => p.concat('Asia/Riyadh'));
const WORLD = places.filter((p) => p[4] !== 'Asia/Riyadh');
const ALL = SAUDI.concat(WORLD);

let lang = store.get('mp-tv-lang') || ((navigator.languages || [navigator.language]).some((l) => /^ar/i.test(l)) ? 'ar' : 'en');
let sound = store.get('mp-tv-sound') === '1';
let nightOn = store.get('mp-tv-night') !== '0';
let city = null, plan = null, planDay = '', daily = null, played = '', unlocked = false, mode = '';
let appList = [], weather = null, netClean = null, wakeUntil = 0;
let row = 0; const col = [0, 0, 0];

const t = () => T[lang];
const rtl = () => lang === 'ar';
const cityName = () => (rtl() ? city.ar : city.en);
const at = (d) => clock(d, city.tz, lang);
const ymd = (d) => new Intl.DateTimeFormat('en-CA', { timeZone: city.tz, year: 'numeric', month: '2-digit', day: '2-digit' }).format(d);
const isFriday = (d) => new Intl.DateTimeFormat('en-US', { timeZone: city.tz, weekday: 'short' }).format(d) === 'Fri';
const name = (k, d) => t().prayers[k === 'dhuhr' && isFriday(d) ? 'jumuah' : k];
const side = () => (rtl() ? 'right' : 'left');
const html = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

function pad(n) { return n < 10 ? '0' + n : '' + n; }
function countdown(ms) {
  const s = Math.max(0, Math.floor(ms / 1000)), h = Math.floor(s / 3600);
  return (h ? h + ':' : '') + pad(Math.floor(s / 60) % 60) + ':' + pad(s % 60);
}
// By XHR: it works over the web and from an installed TV app's own files (file://) alike.
function getJSON(url) {
  return new Promise((ok, fail) => {
    const x = new XMLHttpRequest();
    x.open('GET', url);
    x.timeout = 15000;
    x.onload = () => { try { ok(JSON.parse(x.responseText)); } catch (e) { fail(e); } };
    x.onerror = x.ontimeout = fail;
    x.send();
  });
}

// Icons: thin gold strokes, as in the app.
const ICON = {
  pin: 'M12 21s-6.5-5.6-6.5-11a6.5 6.5 0 0 1 13 0c0 5.4-6.5 11-6.5 11zM12 12.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z',
  lang: 'M4 5h10M9 3v2M6 5c1 4 4 7 7 8M12 5c-1 4-4 7-8 8M13 21l4-10 4 10M14.5 17h5',
  sound: 'M11 5L6 9H3v6h3l5 4V5zM15.5 8.5a5 5 0 0 1 0 7M18.5 5.5a9 9 0 0 1 0 13',
  moon: 'M15.5 3.5a8.5 8.5 0 1 0 5 13.6A7 7 0 0 1 15.5 3.5z',
  gear: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z',
  compass: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM15.5 8.5l-2 5-5 2 2-5z',
  shield: 'M12 3l7 3v5c0 4.5-3 8.3-7 10-4-1.7-7-5.5-7-10V6zM9 12l2 2 4-4',
  clock: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 7v5l3 2',
  clear: 'M12 17a5 5 0 1 0 0-10 5 5 0 0 0 0 10zM12 1.5v2M12 20.5v2M4.6 4.6l1.4 1.4M18 18l1.4 1.4M1.5 12h2M20.5 12h2M4.6 19.4L6 18M18 6l1.4-1.4',
  partly: 'M8 4.5v1.5M3.8 6.3l1 1M2 10.5h1.5M12.2 7.3l1-1M6 13a4 4 0 0 1 7.2-2.4M9 20h9a3.5 3.5 0 0 0 0-7h-.3A5.5 5.5 0 0 0 7 14.5 3 3 0 0 0 9 20z',
  cloudy: 'M7 19h11a4 4 0 0 0 0-8h-.5A6 6 0 0 0 6 12.5 3.5 3.5 0 0 0 7 19z',
  fog: 'M4 10h16M3 14h18M6 18h12M7 6h10',
  rain: 'M7 15h11a4 4 0 0 0 0-8h-.5A6 6 0 0 0 6 8.5 3.5 3.5 0 0 0 7 15zM8 18l-1 2.5M12 18l-1 2.5M16 18l-1 2.5',
  snow: 'M7 14h11a4 4 0 0 0 0-8h-.5A6 6 0 0 0 6 7.5 3.5 3.5 0 0 0 7 14zM8 18h.01M12 18h.01M16 18h.01M10 21h.01M14 21h.01',
  storm: 'M7 14h11a4 4 0 0 0 0-8h-.5A6 6 0 0 0 6 7.5 3.5 3.5 0 0 0 7 14zM12.5 14l-2 4h3l-2 4',
};
const svg = (k) => `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${ICON[k]}"/></svg>`;
function wxKind(code) {
  if (code === 0) return 'clear';
  if (code <= 2) return 'partly';
  if (code === 3) return 'cloudy';
  if (code === 45 || code === 48) return 'fog';
  if (code >= 51 && code <= 57) return 'drizzle';
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return 'rain';
  if ((code >= 71 && code <= 77) || code === 85 || code === 86) return 'snow';
  if (code >= 95) return 'storm';
  return 'cloudy';
}
const wxIcon = (k, day) => (k === 'clear' && !day ? 'moon' : k === 'drizzle' ? 'rain' : k);

// The verse and hadith of the day: the same pick as the app (days since the epoch, round the list), for the city's date.
function dailyPick(now) {
  if (!daily) return null;
  const [y, m, d] = ymd(now).split('-').map(Number), [ey, em, ed] = daily.epoch.split('-').map(Number);
  const days = Math.round((Date.UTC(y, m - 1, d) - Date.UTC(ey, em - 1, ed)) / 864e5);
  const mod = (n, c) => ((n % c) + c) % c;
  return { ayah: daily.ayat[mod(days, daily.ayat.length)], hadith: daily.hadith[mod(days, daily.hadith.length)] };
}

// Which screen: the Adhan from its time until the iqama, the night screen late at night, else the home screen.
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
  if (ymd(now) !== planDay) { plan = schedule(city); planDay = ymd(now); renderToday(); }
  const tx = t(), adhan = adhanNow(now), awake = now < wakeUntil;
  if (adhan) playAdhan(planDay + adhan.k);
  if (adhan && !awake) {
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
    return;
  }
  const next = nextPrayer(plan, now);
  const night = nightOn && !awake && $('#picker').hidden && nightSpan(now);
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
  if (mode !== 'board') { show('board'); place(); }
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
  if (now.getSeconds() === 0) renderTimesCard(now);
  // A few pixels' drift every three minutes, against burn-in on screens left on all day.
  if (now - lastShift > 3 * MIN) {
    lastShift = +now;
    $('#board').style.transform = `translate(${(Math.random() - 0.5) * 0.6}vw, ${(Math.random() - 0.5) * 0.6}vh)`;
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
    $('#marks').innerHTML = plan.today.map(([k, v]) => {
      const cls = 'mark' + (k === 'sunrise' ? ' sunrise' : '') + (k === next[0] && +v === +next[1] ? ' next' : v <= now ? ' past' : '');
      return `<div class="${cls}" style="${side()}:${pct(+v)}%"><span>${html(name(k, now))}</span><i></i><b>${html(at(v))}</b></div>`;
    }).join('');
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
    ref = (rtl() ? 'سورة ' + pick.ayah.surah.ar : pick.ayah.surah.translit) + ' · ' + pick.ayah.ref;
  } else {
    ar = '«' + pick.hadith.ar.text + '»'; tr = pick.hadith.en;
    ref = pick.hadith.ar.grade + tx.sourceSep + pick.hadith.ar.source + tx.sourceSep + 'HadeethEnc.com';
  }
  $('#daily-label').textContent = ayahTurn ? tx.ayah : tx.hadith;
  const el = $('#daily-ar');
  if (el.textContent !== ar) {
    el.textContent = ar;
    el.className = 'daily-ar' + (ar.length > 230 ? ' longer' : ar.length > 120 ? ' long' : '');
  }
  $('#daily-tr').textContent = rtl() ? '' : tr;
  $('#daily-ref').textContent = ref;
}

// MARK: - The rows

function renderShelf() {
  const tx = t();
  const tiles = appList.map((a) => {
    const initial = html((a.title || '?').trim().charAt(0).toUpperCase());
    const ic = a.icon ? `<img src="${html(a.icon)}" alt="">` : initial;
    const bg = a.icon ? 'transparent' : html(a.color || '#24415E');
    return `<div class="app" data-app="${html(a.id)}"><div class="ic" style="background:${bg}">${ic}</div><span>${html(a.title)}</span></div>`;
  });
  tiles.push(`<div class="app" data-act="tv-settings"><div class="ic">${svg('gear')}</div><span>${html(tx.tvSettings)}</span></div>`);
  $('#shelf').innerHTML = tiles.join('');
  // An icon that doesn't load becomes the app's initial on its colour.
  Array.prototype.forEach.call($('#shelf').querySelectorAll('img'), (img) => {
    img.onerror = () => {
      const box = img.parentNode, tile = box.parentNode;
      box.style.background = '#24415E';
      box.textContent = (tile.textContent || '?').trim().charAt(0).toUpperCase();
    };
  });
  place();
}

function renderTimesCard(now) {
  const el = $('#times-card');
  if (!el || !plan) return;
  const next = nextPrayer(plan, now || new Date());
  el.innerHTML = plan.today.map(([k, v]) => {
    const cls = k === next[0] && +v === +next[1] ? ' class="is-next"' : '';
    return `<span${cls}>${html(name(k, v))}</span><b${cls}>${html(at(v))}</b>`;
  }).join('');
}

function renderToday() {
  if (!city) return;
  const tx = t(), q = qibla(city);
  let wx = `<div class="card" data-act="none"><small>${html(tx.weather)} · ${html(cityName())}</small><p class="sub">…</p></div>`;
  if (weather && weather.current) {
    const c = weather.current, d = weather.daily, kind = wxKind(c.weather_code);
    const days = [];
    for (let i = 1; i < Math.min(4, d.time.length); i++) {
      const date = new Date(d.time[i] + 'T12:00:00Z');
      days.push(`<div>${html(tx.day(date))}<span class="wx">${svg(wxIcon(wxKind(d.weather_code[i]), true))}</span><b>${Math.round(d.temperature_2m_max[i])}°</b></div>`);
    }
    wx = `<div class="card" data-act="none"><small>${html(tx.weather)} · ${html(cityName())}</small>
      <div style="display:flex;align-items:center;gap:1.2vw"><span class="wx">${svg(wxIcon(kind, c.is_day))}</span><p class="big">${Math.round(c.temperature_2m)}°</p></div>
      <b>${html(tx.wx[kind])}</b><p class="sub">${html(tx.hiLo(Math.round(d.temperature_2m_max[0]), Math.round(d.temperature_2m_min[0])))}</p>
      <div class="days">${days.join('')}</div></div>`;
  }
  const times = `<div class="card" data-act="none"><small>${html(tx.times)}</small><div id="times-card" class="times-list"></div></div>`;
  const qib = `<div class="card" data-act="none"><small>${html(tx.qibla)}</small><span class="ic">${svg('compass')}</span>
    <p class="big">${q.deg}°</p><p class="sub">${html(tx.fromNorth)}<br>${html(tx.toMakkah(q.km))}</p></div>`;
  const net = netClean === null ? '' : `<div class="card" data-act="none"><small>${html(tx.net)}</small><span class="ic">${svg('shield')}</span>
    <b class="${netClean ? 'mint' : ''}">${html(netClean ? tx.netClean : tx.netAds)}</b><p class="sub">${html(netClean ? tx.netOk : tx.netHow)}</p></div>`;
  $('#today').innerHTML = wx + times + qib + net;
  renderTimesCard();
  place();
}

function renderPrefs() {
  const tx = t();
  const pref = (act, icon, label, value) => `<div class="card pref" data-act="${act}"><span class="ic">${svg(icon)}</span><span><small>${html(label)}</small><b>${html(value)}</b></span></div>`;
  $('#prefs').innerHTML = [
    pref('city', 'pin', tx.city, cityName()),
    pref('lang', 'lang', tx.lang, tx.langName),
    pref('sound', 'sound', tx.sound, sound ? tx.on : tx.off),
    pref('night', 'moon', tx.night, nightOn ? tx.auto : tx.off),
    pref('tv-settings', 'gear', tx.tvSettings, tx.open),
  ].join('');
  place();
}

// MARK: - Focus, by remote: the rows go up and down, the items in a row left and right.

const ROWS = ['apps', 'today', 'settings'];
const items = (r) => Array.prototype.slice.call(document.querySelectorAll(r === 0 ? '#shelf .app' : r === 1 ? '#today .card' : '#prefs .card'));

function place() {
  Array.prototype.forEach.call(document.querySelectorAll('.focus'), (el) => el.classList.remove('focus'));
  const list = items(row);
  if (!list.length) return;
  col[row] = Math.max(0, Math.min(col[row], list.length - 1));
  list[col[row]].classList.add('focus');
  // The page slides to the row; the first row keeps the prayer board in view.
  const sec = document.querySelector(`.row[data-row="${ROWS[row]}"]`);
  const most = $('#page').offsetHeight - window.innerHeight;
  const y = row === 0 ? 0 : Math.min(sec.offsetTop - window.innerHeight * 0.06, Math.max(0, most));
  $('#page').style.transform = `translateY(${-y}px)`;
  // The shelf slides so the focused app stays on screen.
  if (row === 0 && list.length > 1) {
    const step = Math.abs(list[1].offsetLeft - list[0].offsetLeft), fit = Math.floor($('.shelf-clip').clientWidth / step) - 1;
    const shift = Math.max(0, Math.min(col[0] - fit + 1, list.length - fit - 1)) * step;
    $('#shelf').style.transform = `translateX(${rtl() ? shift : -shift}px)`;
  }
}

let hintTimer = 0;
function hint() {
  const tx = t(), el = $('#hint');
  el.textContent = row === 0 ? tx.hintApps : row === 1 ? tx.hintRows : tx.hintPrefs;
  el.classList.remove('gone');
  clearTimeout(hintTimer);
  hintTimer = setTimeout(() => el.classList.add('gone'), 6000);
}

function activate(el) {
  if (!el) return;
  const id = el.getAttribute('data-app'), act = el.getAttribute('data-act');
  if (id) { apps.launch(id); return; }
  if (act === 'tv-settings') apps.settings();
  else if (act === 'city') openPicker();
  else if (act === 'lang') { lang = rtl() ? 'en' : 'ar'; store.set('mp-tv-lang', lang); render(); }
  else if (act === 'sound') { sound = !sound; store.set('mp-tv-sound', sound ? '1' : '0'); unlockAudio(); renderPrefs(); }
  else if (act === 'night') { nightOn = !nightOn; store.set('mp-tv-night', nightOn ? '1' : '0'); renderPrefs(); }
}

// MARK: - The city list: the Kingdom's cities first, then the world's; Up and Down, OK, Back.

let pick = 0, pickRows = [];
function openPicker() {
  const tx = t(), saved = store.get('mp-tv-city');
  pickRows = [{ auto: true, label: tx.autoCity }, { group: tx.saudi }]
    .concat(SAUDI.map((p) => ({ p, label: rtl() ? p[1] : p[0] })))
    .concat([{ group: tx.world }])
    .concat(WORLD.map((p) => ({ p, label: rtl() ? p[1] : p[0] })));
  pick = saved ? Math.max(0, pickRows.findIndex((r) => r.p && r.p[0] === saved)) : 0;
  $('#picker-h').textContent = tx.pickCity;
  $('#picker-keys').textContent = tx.pickKeys;
  $('#picker-list').innerHTML = pickRows.map((r) => (r.group ? `<li class="group">${html(r.group)}</li>` : `<li>${html(r.label)}</li>`)).join('');
  $('#picker').hidden = false;
  movePicker(0);
}
function movePicker(step) {
  let i = pick;
  do { i = Math.max(0, Math.min(pickRows.length - 1, i + step)); } while (pickRows[i].group && i > 0 && i < pickRows.length - 1 && step);
  if (pickRows[i].group) i = pick;
  pick = i;
  const lis = $('#picker-list').children;
  Array.prototype.forEach.call(lis, (li, k) => li.classList.toggle('on', k === pick));
  const list = $('#picker-list'), li = lis[pick];
  list.scrollTop = li.offsetTop - list.clientHeight / 2 + li.offsetHeight / 2;
}
function choosePicker() {
  const r = pickRows[pick];
  $('#picker').hidden = true;
  if (r.auto) { store.set('mp-tv-city', null); } else store.set('mp-tv-city', r.p[0]);
  resolveCity(ALL, '../assets/zones.json', store.get('mp-tv-city')).then((c) => { city = c; weather = null; render(); loadWeather(); });
}

// MARK: - The rest

function render() {
  const tx = t(), now = new Date();
  document.documentElement.lang = lang;
  document.documentElement.dir = rtl() ? 'rtl' : 'ltr';
  $('#city').textContent = cityName();
  $('#date').textContent = new Intl.DateTimeFormat(rtl() ? 'ar-SA-u-ca-gregory-nu-latn' : 'en-GB', { timeZone: city.tz, weekday: 'long', day: 'numeric', month: 'long' }).format(now);
  try {
    $('#hijri').textContent = new Intl.DateTimeFormat((rtl() ? 'ar-SA' : 'en-GB') + '-u-ca-islamic-umalqura-nu-latn', { timeZone: city.tz, day: 'numeric', month: 'long', year: 'numeric' }).format(now);
  } catch (e) { $('#hijri').textContent = ''; }
  $('#next-label').textContent = tx.next;
  $('#remain-l').textContent = tx.remain;
  $('#net-l').textContent = tx.net;
  $('#net').textContent = tx.netClean;
  $('#apps-h').textContent = tx.apps;
  $('#today-h').textContent = tx.today;
  $('#settings-h').textContent = tx.settings;
  plan = schedule(city); planDay = ymd(now);
  lineKey = ''; mode = '';
  renderShelf();
  renderToday();
  renderPrefs();
  renderWeatherChip();
  tick();
}

function loadWeather() {
  const c = city;
  const url = 'https://api.open-meteo.com/v1/forecast?latitude=' + c.lat + '&longitude=' + c.lon +
    '&current=temperature_2m,weather_code,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=4';
  getJSON(url).then((w) => { if (c === city) { weather = w; renderToday(); renderWeatherChip(); } }).catch(() => {});
}
function renderWeatherChip() {
  const ok = weather && weather.current;
  $('#chip-wx').hidden = !ok;
  if (!ok) return;
  const kind = wxKind(weather.current.weather_code);
  $('#wx-chip-l').textContent = t().wx[kind];
  $('#wx-chip').textContent = Math.round(weather.current.temperature_2m) + '°';
}

// "Clean · no ads" only when it's true: an ad server doesn't answer while an ordinary site does, which is what a
// blocking DNS (AdGuard, the router's or the TV's) does.
function checkNetwork() {
  if (typeof fetch !== 'function') return;
  const reach = (u) => fetch(u, { mode: 'no-cors', cache: 'no-store' }).then(() => true, () => false);
  Promise.all([reach('https://www.google.com/generate_204'), reach('https://googleads.g.doubleclick.net/pagead/id')])
    .then(([web, ads]) => {
      if (!web) return;
      netClean = !ads;
      $('#chip-net').hidden = !netClean;
      renderToday();
    });
}

// A TV plays sound only after a key press on the page: the first key primes the Adhan, silently.
function unlockAudio() {
  if (unlocked || !sound) return;
  const a = $('#adhan-audio');
  a.muted = true;
  const p = a.play();
  const done = () => { a.pause(); a.muted = false; a.currentTime = 0; unlocked = true; };
  if (p && p.then) p.then(done, () => { a.muted = false; }); else done();
}

const BACK = { Escape: 1, Backspace: 1, GoBack: 1, BrowserBack: 1 };
const KEYS = { 37: 'left', 38: 'up', 39: 'right', 40: 'down', 13: 'ok' };
addEventListener('keydown', (e) => {
  const back = BACK[e.key] || e.keyCode === 10009 || e.keyCode === 461;
  const k = back ? 'back' : KEYS[e.keyCode];
  if (!k) return;
  e.preventDefault();
  unlockAudio();
  // On the Adhan or night screen a key first wakes the home screen (OK first stops a playing Adhan).
  if (mode !== 'board') {
    if (k === 'ok' && stopAdhan()) { tick(); return; }
    wakeUntil = Date.now() + WAKE;
    tick(); hint();
    return;
  }
  wakeUntil = Math.max(wakeUntil, Date.now() + WAKE);
  if (!$('#picker').hidden) {
    if (k === 'up') movePicker(-1);
    else if (k === 'down') movePicker(1);
    else if (k === 'ok') choosePicker();
    else if (k === 'back') $('#picker').hidden = true;
    return;
  }
  if (k === 'back') {
    if (row > 0) { row = 0; place(); hint(); } else apps.back();
    return;
  }
  if (k === 'ok') { activate(items(row)[col[row]]); return; }
  if (k === 'up' || k === 'down') {
    row = Math.max(0, Math.min(ROWS.length - 1, row + (k === 'down' ? 1 : -1)));
  } else {
    const forward = (k === 'left') === rtl();
    col[row] += forward ? 1 : -1;
  }
  place(); hint();
});
// LG's Magic Remote points and clicks.
addEventListener('click', (e) => {
  unlockAudio();
  if (mode !== 'board') { wakeUntil = Date.now() + WAKE; tick(); return; }
  const li = e.target.closest ? e.target.closest('#picker-list li') : null;
  if (li && !li.classList.contains('group')) { pick = Array.prototype.indexOf.call(li.parentNode.children, li); choosePicker(); return; }
  const el = e.target.closest ? e.target.closest('.app, .card') : null;
  if (!el) return;
  for (let r = 0; r < ROWS.length; r++) {
    const i = items(r).indexOf(el);
    if (i >= 0) { row = r; col[r] = i; place(); activate(el); return; }
  }
});
addEventListener('resize', () => { lineKey = ''; place(); tick(); });

// Keep the screen on: the browser's wake lock where there is one; on an LG TV, the app answers the TV's screensaver
// request with "not now", as LG's video apps do.
function keepAwake() { try { if (navigator.wakeLock) navigator.wakeLock.request('screen').catch(() => {}); } catch (e) { /* not offered */ } }
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState !== 'visible') return;
  keepAwake();
  // Back from an app: the apps may have changed, and the home screen starts at the top.
  row = 0; apps.list((l) => { appList = l; renderShelf(); });
});
function holdScreensaver() {
  if (!apps.webos) return;
  const svc = 'luna://com.webos.service.tvpower/power/', id = 'sa.zood.mosquepro.tv';
  const reg = new window.PalmServiceBridge();
  reg.onservicecallback = (msg) => {
    let r = {};
    try { r = JSON.parse(msg); } catch (e) { return; }
    if (r.state === 'Active' && r.timestamp) {
      const ans = new window.PalmServiceBridge();
      ans.call(svc + 'responseScreenSaverRequest', JSON.stringify({ clientName: id, ack: false, timestamp: r.timestamp }));
      window.__mpAns = ans;
    }
  };
  reg.call(svc + 'registerScreenSaverRequest', JSON.stringify({ subscribe: true, clientName: id }));
  window.__mpSaver = reg; // keeps the subscription alive
}

resolveCity(ALL, '../assets/zones.json', store.get('mp-tv-city')).then((c) => {
  city = c;
  render();
  hint();
  keepAwake();
  holdScreensaver();
  checkNetwork();
  loadWeather();
  apps.list((l) => { appList = l; renderShelf(); });
  setInterval(tick, 1000);
  setInterval(checkNetwork, 30 * MIN);
  setInterval(loadWeather, 30 * MIN);
  getJSON('daily.json').then((d) => { daily = d; tick(); }).catch(() => {});
});
