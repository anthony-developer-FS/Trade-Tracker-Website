/**
 * The one shared Supabase client, as TradeLab.supabase.
 *
 * Load order on every page that talks to Supabase (all with defer):
 *   1. supabase-js from the CDN       (defines window.supabase)
 *   2. assets/js/config.js            (defines window.TRADELAB_CONFIG)
 *   3. assets/js/lib/supabase.js      (this file)
 *   4. assets/js/lib/auth.js, then the page script
 *
 * If config.js is missing or still has the placeholder values, the client is
 * null and TradeLab.supabaseError says what to fix, so pages can show it
 * instead of failing silently.
 */
(function () {
  'use strict';

  // "Keep me logged in" on the login page. Unchecked keeps the session in
  // sessionStorage, so it ends when the browser closes.
  var REMEMBER_KEY = 'tradelab-remember';

  window.TradeLab = window.TradeLab || {};

  function safeStorage(name) {
    try {
      var storage = window[name];
      var probe = '__tradelab__';
      storage.setItem(probe, probe);
      storage.removeItem(probe);
      return storage;
    } catch (error) {
      return null; // blocked (private mode, strict settings)
    }
  }

  var local = safeStorage('localStorage');
  var session = safeStorage('sessionStorage');

  function remember() {
    return !local || local.getItem(REMEMBER_KEY) !== 'false';
  }

  // Storage adapter for supabase-js. Reads from either store, writes to the
  // one that matches the "Keep me logged in" choice.
  var authStorage = {
    getItem: function (key) {
      return (session && session.getItem(key)) || (local && local.getItem(key)) || null;
    },
    setItem: function (key, value) {
      var keep = remember();
      var target = keep ? local : session;
      var other = keep ? session : local;
      if (other) other.removeItem(key);
      if (target) target.setItem(key, value);
    },
    removeItem: function (key) {
      if (local) local.removeItem(key);
      if (session) session.removeItem(key);
    }
  };

  function configError(config) {
    if (!window.supabase || typeof window.supabase.createClient !== 'function') {
      return 'The Supabase library did not load. Check your internet connection.';
    }
    if (!config) {
      return 'Supabase is not configured. Copy assets/js/config.example.js to assets/js/config.js and add your project URL and anon key.';
    }
    if (!config.supabaseUrl || !config.supabaseAnonKey ||
        config.supabaseUrl.indexOf('YOUR-PROJECT-REF') !== -1 ||
        config.supabaseAnonKey.indexOf('YOUR-') === 0) {
      return 'assets/js/config.js still has the placeholder values. Add your Supabase project URL and anon key.';
    }
    return null;
  }

  var config = window.TRADELAB_CONFIG;
  var error = configError(config);

  window.TradeLab.supabaseError = error;
  window.TradeLab.supabase = null;

  if (error) {
    console.error('[TradeLab] ' + error);
    return;
  }

  window.TradeLab.supabase = window.supabase.createClient(config.supabaseUrl, config.supabaseAnonKey, {
    auth: {
      storage: authStorage,
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true // picks up the session from confirmation and reset links
    }
  });

  window.TradeLab.setRememberMe = function (keep) {
    if (local) local.setItem(REMEMBER_KEY, keep ? 'true' : 'false');
  };
})();
