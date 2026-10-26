// The TV's apps for the Mosque Pro home screen: listing and opening them, the TV's settings, and Back.
//  - LG webOS: the TV's service bus (Luna), as LG's own launcher does. Developer Mode apps on webOS 6 and newer may
//    be refused the list; then the apps the TV says it has, from a short list of common ones, are shown.
//  - Samsung (Tizen) app: tizen.application lists the apps the TV shows and opens them; Back on the home screen
//    closes it.
//  - Any other browser: sample apps, so the screen can be tried on a computer.
// Plain script (no modules) so it loads the same in a TV app and on the web; it defines window.TVApps.
(function () {
  'use strict';
  var webos = typeof window.PalmServiceBridge !== 'undefined';
  // The Samsung app (a Tizen web app) lists and opens the TV's apps through tizen.application.
  var tizen = !webos && !!(window.tizen && window.tizen.application);
  var held = []; // a bridge must be kept until it answers

  function luna(uri, params, done) {
    if (!webos) { setTimeout(function () { done(null); }, 0); return; }
    var b = new window.PalmServiceBridge(), over = false;
    held.push(b);
    b.onservicecallback = function (msg) {
      if (over) return;
      over = true;
      held.splice(held.indexOf(b), 1);
      var r = null;
      try { r = JSON.parse(msg); } catch (e) { /* not JSON */ }
      done(r && r.returnValue !== false ? r : null);
    };
    b.call(uri, JSON.stringify(params || {}));
  }

  var self = 'sa.zood.mosquepro.tv';
  // LG's home, launchers and inputs aren't apps to show; the TV's settings get their own tile.
  var HIDDEN = /^(com\.webos\.app\.(home|homeconnect|discovery|launcher|inputpicker|livemenu)|com\.palm\.app\.settings|io\.freemytv.*)$/;
  var COMMON = [
    ['netflix', 'Netflix', '#E50914'], ['youtube.leanback.v4', 'YouTube', '#FF0033'], ['amazon', 'Prime Video', '#1A98FF'],
    ['com.disney.disneyplus-prod', 'Disney+', '#1838C8'], ['shahid', 'Shahid', '#2A9D8F'], ['com.apple.appletv', 'Apple TV', '#B8BCC6'],
    ['spotify-beehive', 'Spotify', '#1DB954'], ['com.webos.app.livetv', 'Live TV', '#3A7BD5'], ['com.webos.app.hdmi1', 'HDMI 1', '#6B7280'],
    ['com.webos.app.hdmi2', 'HDMI 2', '#6B7280'], ['com.webos.app.browser', 'Web Browser', '#3A7BD5']
  ];

  function common(done) {
    var found = [], left = COMMON.length, sent = false;
    function finish() { if (!sent) { sent = true; done(found.filter(Boolean)); } }
    setTimeout(finish, 4000);
    COMMON.forEach(function (c, i) {
      luna('luna://com.webos.applicationManager/getAppLoadStatus', { appId: c[0] }, function (r) {
        if (r && r.exist) found[i] = { id: c[0], title: c[1], icon: '', color: c[2] };
        if (--left === 0) finish();
      });
    });
  }

  // Clean logos for the best-known apps, drawn the same way on every TV: [name, tile colour, 24×24 path]. From Simple
  // Icons (simpleicons.org, CC0); the brands are their owners' and are shown only to open their apps.
  var BRANDS = [
    [/netflix/i, '#E50914', 'M5.398 0v.006c3.028 8.556 5.37 15.175 8.348 23.596 2.344.058 4.85.398 4.854.398-2.8-7.924-5.923-16.747-8.487-24zm8.489 0v9.63L18.6 22.951c-.043-7.86-.004-15.913.002-22.95zM5.398 1.05V24c1.873-.225 2.81-.312 4.715-.398v-9.22z'],
    [/youtube ?music/i, '#FF0000', 'M12 0C5.376 0 0 5.376 0 12s5.376 12 12 12 12-5.376 12-12S18.624 0 12 0zm0 19.104c-3.924 0-7.104-3.18-7.104-7.104S8.076 4.896 12 4.896s7.104 3.18 7.104 7.104-3.18 7.104-7.104 7.104zm0-13.332c-3.432 0-6.228 2.796-6.228 6.228S8.568 18.228 12 18.228s6.228-2.796 6.228-6.228S15.432 5.772 12 5.772zM9.684 15.54V8.46L15.816 12l-6.132 3.54z'],
    [/youtube/i, '#FF0000', 'M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z'],
    [/prime ?video|amazon/i, '#00A8E1', 'M0 9.508c0-.043.01-.073.028-.09.018-.017.047-.025.086-.025h.329c.07 0 .112.034.127.101l.032.119c.091-.088.202-.159.33-.21a1.04 1.04 0 0 1 .396-.079c.294 0 .528.109.7.326.171.217.257.51.257.88 0 .254-.042.475-.127.665-.086.19-.201.335-.347.437a.85.85 0 0 1-.502.154c-.125 0-.243-.02-.355-.06a.857.857 0 0 1-.288-.164v1.003c0 .043-.008.073-.025.09-.017.016-.046.025-.09.025H.115c-.04 0-.068-.009-.086-.025-.019-.017-.028-.047-.028-.09zm1.113.32a.868.868 0 0 0-.447.124v1.206a.834.834 0 0 0 .447.124c.17 0 .296-.058.376-.174.081-.117.121-.3.121-.55 0-.254-.04-.439-.118-.555-.08-.116-.206-.174-.379-.174zm2.248-.087c.121-.134.236-.23.344-.286a.733.733 0 0 1 .345-.085h.063c.043 0 .073.009.092.025.018.017.027.047.027.09v.385c0 .04-.008.068-.025.087-.017.018-.046.027-.089.027a.923.923 0 0 1-.082-.004 1.369 1.369 0 0 0-.383.025c-.1.02-.186.045-.256.076v1.54c0 .04-.008.069-.025.087-.016.018-.046.028-.089.028h-.437c-.04 0-.069-.01-.087-.028-.018-.018-.028-.047-.028-.087V9.508c0-.043.01-.073.028-.09.018-.017.047-.025.087-.025h.328c.07 0 .112.034.128.1zm1.526-.71a.396.396 0 0 1-.278-.096.338.338 0 0 1-.105-.262c0-.11.035-.197.105-.26a.395.395 0 0 1 .278-.097c.116 0 .208.032.278.096.07.064.105.151.105.261a.34.34 0 0 1-.105.262.396.396 0 0 1-.278.096zm-.333.477c0-.043.01-.073.027-.09.019-.017.048-.025.087-.025h.438c.043 0 .072.008.089.025s.025.047.025.09v2.113c0 .04-.008.069-.025.087-.017.018-.046.028-.09.028h-.437c-.04 0-.068-.01-.087-.028-.018-.018-.027-.047-.027-.087zm1.837.11c.161-.107.306-.183.435-.227.13-.045.263-.067.4-.067.273 0 .466.098.579.294.155-.104.3-.18.438-.225.137-.046.278-.069.424-.069.213 0 .377.06.495.179.117.12.175.286.175.5v1.618c0 .04-.008.069-.025.087-.017.019-.046.027-.089.027h-.438c-.04 0-.068-.008-.086-.027-.018-.018-.028-.047-.028-.087V10.15c0-.208-.092-.312-.278-.312-.164 0-.33.04-.497.119v1.664c0 .04-.008.069-.025.087-.017.019-.046.027-.09.027h-.437c-.04 0-.068-.008-.086-.027-.019-.018-.028-.047-.028-.087V10.15c0-.208-.093-.312-.278-.312-.17 0-.337.04-.502.123v1.66c0 .04-.008.069-.025.087-.017.019-.046.027-.089.027h-.438c-.039 0-.068-.008-.086-.027-.018-.018-.027-.047-.027-.087V9.508c0-.043.009-.073.027-.09.018-.017.047-.025.086-.025h.329c.07 0 .112.034.128.101zm4.387 1.16a1.81 1.81 0 0 1-.451-.05c.018.204.08.35.185.44.105.088.263.132.476.132.085 0 .168-.005.249-.016a3.08 3.08 0 0 0 .362-.078.143.143 0 0 1 .023-.002c.052 0 .078.035.078.105v.211c0 .049-.007.083-.02.103a.169.169 0 0 1-.08.053 1.953 1.953 0 0 1-.708.128c-.377 0-.666-.103-.868-.312-.203-.207-.304-.505-.304-.893 0-.398.104-.71.31-.935.207-.227.494-.34.862-.34.283 0 .504.069.664.206a.69.69 0 0 1 .24.55c0 .23-.087.403-.258.52-.172.119-.425.177-.76.177zm.064-.99c-.292 0-.46.18-.506.54.122.025.257.037.406.037.155 0 .267-.024.337-.071.07-.047.105-.12.105-.218 0-.193-.114-.289-.342-.289zm2.948 1.946a.21.21 0 0 1-.075-.011.119.119 0 0 1-.05-.037.274.274 0 0 1-.038-.071l-.777-2.04a1.863 1.863 0 0 1-.023-.063.162.162 0 0 1-.009-.05c0-.047.03-.07.091-.07h.454c.049 0 .084.01.107.028.023.018.04.049.052.092l.468 1.622.477-1.622a.175.175 0 0 1 .052-.092c.023-.018.058-.027.107-.027h.44c.061 0 .091.022.091.068a.16.16 0 0 1-.009.05l-.022.065-.777 2.039a.274.274 0 0 1-.039.07.122.122 0 0 1-.047.038.207.207 0 0 1-.078.01zm2.02-2.703a.393.393 0 0 1-.277-.097.338.338 0 0 1-.105-.26c0-.11.035-.198.105-.262a.393.393 0 0 1 .277-.096c.115 0 .207.032.277.096.07.064.104.151.104.261 0 .11-.034.197-.104.261a.393.393 0 0 1-.277.097zm-.218 2.703c-.04 0-.068-.01-.086-.028-.019-.018-.028-.047-.028-.087V9.507c0-.043.01-.072.028-.09.018-.016.047-.024.086-.024h.436c.042 0 .072.008.089.025.016.017.024.046.024.09v2.111c0 .04-.008.07-.024.087-.017.019-.047.028-.09.028zm1.948.05a.869.869 0 0 1-.513-.153.97.97 0 0 1-.334-.426 1.6 1.6 0 0 1-.116-.63c0-.38.09-.682.268-.91a.856.856 0 0 1 .709-.341.98.98 0 0 1 .622.206V8.458c0-.043.01-.073.027-.09.018-.016.047-.025.087-.025h.436c.042 0 .071.009.088.025.017.017.025.047.025.09v3.161c0 .04-.008.07-.025.087-.017.019-.046.028-.088.028h-.364a.135.135 0 0 1-.084-.023.137.137 0 0 1-.043-.078l-.027-.105a.958.958 0 0 1-.668.256zm.218-.504a.762.762 0 0 0 .418-.128v-1.21a.872.872 0 0 0-.45-.114c-.16 0-.28.06-.358.18-.08.121-.118.304-.118.548 0 .245.041.426.124.546.084.119.212.178.384.178zm2.588-.51c-.169 0-.315-.016-.44-.05.018.201.078.345.18.432.103.087.257.13.465.13.083 0 .164-.005.242-.016a2.997 2.997 0 0 0 .354-.076.135.135 0 0 1 .022-.002c.05 0 .075.035.075.103v.207c0 .048-.007.082-.02.101a.165.165 0 0 1-.077.052 1.895 1.895 0 0 1-.69.126c-.367 0-.65-.102-.846-.306-.197-.204-.296-.496-.296-.876 0-.39.1-.695.302-.917.202-.222.482-.333.84-.333.276 0 .492.068.647.203a.678.678 0 0 1 .234.539c0 .225-.084.395-.251.51-.168.115-.415.173-.74.173zm.063-.97c-.285 0-.45.176-.494.53.119.024.25.036.396.036.15 0 .26-.024.329-.07.068-.046.102-.117.102-.213 0-.19-.111-.284-.333-.284zm2.442 2.003c-.36 0-.642-.11-.845-.328-.203-.218-.304-.523-.304-.914 0-.388.101-.691.304-.91.203-.218.485-.327.845-.327s.642.109.845.327c.203.219.304.522.304.91 0 .39-.101.696-.304.914-.203.218-.485.328-.845.328zm0-.514c.318 0 .477-.242.477-.728 0-.483-.16-.724-.477-.724-.318 0-.477.241-.477.724 0 .486.16.728.477.728zm-6.844 1.886c.405-.306.944-.408 1.39-.408.418 0 .756.09.828.185.15.2-.039 1.584-.775 2.244-.112.102-.22.047-.17-.087.166-.442.536-1.436.36-1.677-.175-.242-1.158-.115-1.6-.058-.068.008-.107-.02-.112-.061v-.023c.004-.036.03-.078.079-.115zm-10.184-.172a.105.105 0 0 1 .106-.091c.027 0 .057.009.089.028a11.778 11.778 0 0 0 6.194 1.772c1.52 0 3.19-.34 4.726-1.043.232-.105.426.164.2.346-1.371 1.09-3.359 1.67-5.07 1.67-2.397 0-4.557-.956-6.191-2.547a.173.173 0 0 1-.054-.097Z'],
    [/spotify/i, '#1ED760', 'M12 0C5.4 0 0 5.4 0 12s5.4 12 12 12 12-5.4 12-12S18.66 0 12 0zm5.521 17.34c-.24.359-.66.48-1.021.24-2.82-1.74-6.36-2.101-10.561-1.141-.418.122-.779-.179-.899-.539-.12-.421.18-.78.54-.9 4.56-1.021 8.52-.6 11.64 1.32.42.18.479.659.301 1.02zm1.44-3.3c-.301.42-.841.6-1.262.3-3.239-1.98-8.159-2.58-11.939-1.38-.479.12-1.02-.12-1.14-.6-.12-.48.12-1.021.6-1.141C9.6 9.9 15 10.561 18.72 12.84c.361.181.54.78.241 1.2zm.12-3.36C15.24 8.4 8.82 8.16 5.16 9.301c-.6.179-1.2-.181-1.38-.721-.18-.601.18-1.2.72-1.381 4.26-1.26 11.28-1.02 15.721 1.621.539.3.719 1.02.419 1.56-.299.421-1.02.599-1.559.3z'],
    [/apple ?tv/i, '#1C1C1E', 'M20.57 17.735h-1.815l-3.34-9.203h1.633l2.02 5.987c.075.231.273.9.586 2.012l.297-.997.33-1.006 2.094-6.004H24zm-5.344-.066a5.76 5.76 0 0 1-1.55.207c-1.23 0-1.84-.693-1.84-2.087V9.646h-1.063V8.532h1.121V7.081l1.476-.602v2.062h1.707v1.113H13.38v5.805c0 .446.074.75.214.932.14.182.396.264.75.264.207 0 .495-.041.883-.115zm-7.29-5.343c.017 1.764 1.55 2.358 1.567 2.366-.017.042-.248.842-.808 1.658-.487.71-.99 1.418-1.79 1.435-.783.016-1.03-.462-1.93-.462-.89 0-1.17.445-1.913.478-.758.025-1.344-.775-1.838-1.484-.998-1.451-1.765-4.098-.734-5.88.51-.89 1.426-1.451 2.416-1.46.75-.016 1.468.512 1.93.512.461 0 1.327-.627 2.234-.536.38.016 1.452.157 2.136 1.154-.058.033-1.278.743-1.27 2.219M6.468 7.988c.404-.495.685-1.18.61-1.864-.585.025-1.294.388-1.723.883-.38.437-.71 1.138-.619 1.806.652.05 1.328-.338 1.732-.825Z'],
    [/crunchyroll/i, '#F47521', 'M2.933 13.467a10.55 10.55 0 1 1 21.067-.8V12c0-6.627-5.373-12-12-12S0 5.373 0 12s5.373 12 12 12h.8a10.617 10.617 0 0 1-9.867-10.533zM19.2 14a3.85 3.85 0 0 1-1.333-7.467A7.89 7.89 0 0 0 14 5.6a8.4 8.4 0 1 0 8.4 8.4 6.492 6.492 0 0 0-.133-1.6A3.415 3.415 0 0 1 19.2 14z'],
    [/twitch/i, '#9146FF', 'M11.571 4.714h1.715v5.143H11.57zm4.715 0H18v5.143h-1.714zM6 0L1.714 4.286v15.428h5.143V24l4.286-4.286h3.428L22.286 12V0zm14.571 11.143l-3.428 3.428h-3.429l-3 3v-3H6.857V1.714h13.714Z'],
    [/plex/i, '#1F1F1F', 'M3.987 8.409c-.96 0-1.587.28-2.12.933v-.72H0v8.88s.038.018.127.037c.138.03.821.187 1.331-.249.441-.377.542-.814.542-1.318v-1.283c.533.573 1.147.813 2 .813 1.84 0 3.253-1.493 3.253-3.48 0-2.12-1.36-3.613-3.266-3.613Zm16.748 5.595.406.591c.391.614.894.906 1.492.908.621-.012 1.064-.562 1.226-.755 0 0-.307-.27-.686-.72-.517-.614-1.214-1.755-1.24-1.803l-1.198 1.779Zm-3.205-1.955c0-2.08-1.52-3.64-3.52-3.64s-3.467 1.587-3.467 3.573a3.48 3.48 0 0 0 3.507 3.52c1.413 0 2.626-.84 3.253-2.293h-2.04l-.093.093c-.427.4-.72.533-1.227.533-.787 0-1.373-.506-1.453-1.266h4.986c.04-.214.054-.307.054-.52Zm-7.671-.219c0 .769.11 1.701.868 2.722l.056.069c-.306.526-.742.88-1.248.88-.399 0-.814-.211-1.138-.579a2.177 2.177 0 0 1-.538-1.441V6.409H9.86l-.001 5.421Zm9.283 3.46h-2.39l2.247-3.332-2.247-3.335h2.39l2.248 3.335-2.248 3.332Zm1.593-1.286Zm-17.162-.342c-.933 0-1.68-.773-1.68-1.72s.76-1.666 1.68-1.666c.92 0 1.68.733 1.68 1.68 0 .946-.733 1.706-1.68 1.706Zm18.361-1.974L24 8.622h-2.391l-.87 1.293 1.195 1.773Zm-9.404-.466c.16-.706.72-1.133 1.493-1.133.773 0 1.373.467 1.507 1.133h-3Z'],
    [/tiktok/i, '#111111', 'M12.525.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z']
  ];
  function brand(title) {
    for (var i = 0; i < BRANDS.length; i++) if (BRANDS[i][0].test(title)) return { color: BRANDS[i][1], path: BRANDS[i][2] };
    return null;
  }
  // Apps people look for first; they lead the row, also when the TV files them under its own ids (Netflix and Prime
  // Video on Samsung).
  var FAVOURITES = /netflix|prime ?video|amazon|youtube|disney|shahid|osn|stc|starz|apple ?tv|spotify|anghami|\btod\b|crunchyroll/i;

  // Samsung: apps from the store (a Tizen app id is a 10-letter package id and a name, or a store number), by name.
  var SAMSUNG_OWN = /^(org\.tizen|com\.samsung|samsung|com\.tizen|tizen|org\.volt|com\.sec)\b/i;
  // Samsung helpers that come with the TV under store-like ids.
  var SAMSUNG_EXTRAS = /^(user guide|e-manual|tv ?device ?care|device care|samsung promotion|smartthings|bixby|gallery|samsung health|internet)$/i;
  // The TV's own Settings app, found by name while listing; the ids are Samsung's guesses for when it isn't listed.
  var SETTINGS = /^(settings|all settings|الإعدادات|كل الإعدادات)$/i;
  var settingsId = '';
  var SETTINGS_IDS = ['com.samsung.tv.menu', 'org.tizen.settings', 'com.samsung.tv.settings'];
  function tizenSettings(fail) {
    var ids = (settingsId ? [settingsId] : []).concat(SETTINGS_IDS);
    (function next(i) {
      if (i >= ids.length) { fail(); return; }
      try { window.tizen.application.launch(ids[i], function () {}, function () { next(i + 1); }); } catch (e) { next(i + 1); }
    })(0);
  }

  function tizenList(done) {
    try {
      window.tizen.application.getAppsInfo(function (infos) {
        var mine = '';
        try { mine = window.tizen.application.getCurrentApplication().appInfo.id; } catch (e) { /* unknown */ }
        var out = [];
        var seen = {};
        infos.forEach(function (a) {
          if (!a.name || a.id === mine) return;
          if (SETTINGS.test(a.name) && !settingsId) settingsId = a.id;
          if (!a.show || seen[a.name]) return;
          // Samsung's own parts of the TV (settings, sources, the store, helpers) aren't apps to show; nor is
          // anything without an icon.
          var fav = FAVOURITES.test(a.name);
          if (!fav && (SAMSUNG_OWN.test(a.id) || SAMSUNG_EXTRAS.test(a.name) || !a.iconPath)) return;
          seen[a.name] = true;
          out.push({ id: a.id, title: a.name, icon: a.iconPath, color: '' });
        });
        // The favourites first, then the rest by name.
        out.sort(function (x, y) {
          var fx = FAVOURITES.test(x.title) ? 0 : 1, fy = FAVOURITES.test(y.title) ? 0 : 1;
          return fx - fy || x.title.localeCompare(y.title);
        });
        done(out);
      }, function () { done([]); });
    } catch (e) { done([]); }
  }

  window.TVApps = {
    webos: webos,
    /** True where the page can open the TV's apps (the LG and Samsung apps, not a web browser). */
    opens: webos || tizen,
    /** The installed apps: [{id, title, icon, color}], in the TV's own order. */
    list: function (done) {
      if (tizen) { tizenList(done); return; }
      if (!webos) {
        done(COMMON.slice(0, 7).map(function (c) { return { id: c[0], title: c[1], icon: '', color: c[2] }; }));
        return;
      }
      luna('luna://com.webos.applicationManager/listLaunchPoints', {}, function (r) {
        if (!r || !r.launchPoints) { common(done); return; }
        var out = [];
        r.launchPoints.forEach(function (p) {
          if (!p.id || p.id === self || HIDDEN.test(p.id)) return;
          out.push({ id: p.id, title: p.title || p.id, icon: p.largeIcon || p.icon || '', color: p.bgColor || p.iconColor || '' });
        });
        done(out);
      });
    },
    launch: function (id) {
      if (tizen) { try { window.tizen.application.launch(id, function () {}, function () {}); } catch (e) { /* not allowed */ } return; }
      luna('luna://com.webos.applicationManager/launch', { id: id }, function () {});
    },
    /** The TV's settings; `fail` runs where they can't be opened from here. */
    settings: function (fail) {
      if (tizen) { tizenSettings(fail); return; }
      if (!webos) { fail(); return; }
      luna('luna://com.webos.applicationManager/launch', { id: 'com.palm.app.settings' }, function () {});
    },
    /** A clean logo for a well-known app: {color, path}, or null. */
    brand: brand,
    /** Back on the home screen: leave the app, to wherever the person came from. */
    back: function () {
      if (window.PalmSystem && window.PalmSystem.platformBack) window.PalmSystem.platformBack();
      else if (webos) window.close();
      else if (window.tizen && window.tizen.application) window.tizen.application.getCurrentApplication().exit();
    },
  };
})();
