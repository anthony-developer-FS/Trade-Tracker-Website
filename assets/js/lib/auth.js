/**
 * Sign-in state shared by every page that loads Supabase: the page guard,
 * log out, the account menu and small form helpers for the auth pages.
 * Load after assets/js/lib/supabase.js (see the load order there).
 *
 * Markup hooks:
 *   <body data-auth="required">  page needs a signed-in user; anyone else is
 *                                sent to login.html?next=<this page>
 *   <body data-auth="guest">     log in / sign up; a signed-in user is sent on
 *                                to ?next= or the trade log
 *   [data-action="sign-out"]     button that logs out and goes to the home page
 *   [data-user-name]             filled with the user's name
 *   [data-user-initials]         filled with the user's initials (avatar)
 *   [data-user-email]            filled with the user's email
 *
 * Page scripts wait for the signed-in user with:
 *   TradeLab.auth.ready.then(function (user) { ... })   // user or null
 */
(function () {
  'use strict';

  var DEFAULT_APP_PAGE = 'app/trades.html';

  window.TradeLab = window.TradeLab || {};
  var supabase = window.TradeLab.supabase;

  // The site root, worked out from this file's own URL
  // (assets/js/lib/auth.js), so it works on localhost, a custom domain or
  // a subfolder like GitHub Pages without any settings.
  var SITE_ROOT = new URL('../../../', document.currentScript.src).href;

  function siteUrl(path) {
    return new URL(path || '', SITE_ROOT).href;
  }

  // The current page as a path relative to the site root, for ?next=.
  function currentPagePath() {
    var here = window.location.href.split('#')[0];
    return here.indexOf(SITE_ROOT) === 0 ? here.slice(SITE_ROOT.length) : DEFAULT_APP_PAGE;
  }

  // Where to go after logging in. Only pages on this site are accepted, so
  // ?next= can't be used to send someone to another website.
  function nextUrl() {
    var next = new URLSearchParams(window.location.search).get('next');
    if (next && !/^[a-z][a-z0-9+.-]*:/i.test(next) && next.indexOf('//') !== 0 && next.indexOf('\\') === -1) {
      var url = new URL(next, SITE_ROOT);
      if (url.href.indexOf(SITE_ROOT) === 0) return url.href;
    }
    return siteUrl(DEFAULT_APP_PAGE);
  }

  function loginUrl(next) {
    return siteUrl('login.html') + (next ? '?next=' + encodeURIComponent(next) : '');
  }

  /* ---------------------------------------------------------------------------
   * Account menu
   * ------------------------------------------------------------------------- */

  function displayName(user) {
    var meta = user.user_metadata || {};
    return meta.full_name || meta.name || (user.email || '').split('@')[0];
  }

  function initials(name) {
    var parts = name.trim().split(/\s+/).filter(Boolean);
    if (!parts.length) return '?';
    var first = parts[0].charAt(0);
    var last = parts.length > 1 ? parts[parts.length - 1].charAt(0) : '';
    return (first + last).toUpperCase();
  }

  function fillUser(user) {
    var name = displayName(user);
    document.querySelectorAll('[data-user-name]').forEach(function (el) { el.textContent = name; });
    document.querySelectorAll('[data-user-initials]').forEach(function (el) { el.textContent = initials(name); });
    document.querySelectorAll('[data-user-email]').forEach(function (el) { el.textContent = user.email || ''; });
  }

  /* ---------------------------------------------------------------------------
   * Log out
   * ------------------------------------------------------------------------- */

  var signingOut = false;

  function signOut() {
    signingOut = true;
    var done = function () { window.location.assign(siteUrl('index.html')); };
    if (!supabase) return done();
    // Even if the request fails (offline), the local session is cleared.
    return supabase.auth.signOut().then(done, done);
  }

  function initSignOut() {
    document.addEventListener('click', function (event) {
      var button = event.target.closest('[data-action="sign-out"]');
      if (!button) return;
      event.preventDefault();
      button.disabled = true;
      signOut();
    });
  }

  /* ---------------------------------------------------------------------------
   * Page guard
   * ------------------------------------------------------------------------- */

  function getUser() {
    if (!supabase) return Promise.resolve(null);
    return supabase.auth.getSession().then(function (result) {
      var session = result.data && result.data.session;
      return session ? session.user : null;
    }, function () {
      return null;
    });
  }

  var mode = document.body ? document.body.getAttribute('data-auth') : null;

  var ready = getUser().then(function (user) {
    if (mode === 'required' && !user) {
      window.location.replace(loginUrl(currentPagePath()));
      return new Promise(function () {}); // never resolves; the page is leaving
    }
    if (mode === 'guest' && user) {
      window.location.replace(nextUrl());
      return new Promise(function () {});
    }
    if (user) fillUser(user);
    return user;
  });

  if (supabase) {
    supabase.auth.onAuthStateChange(function (event, session) {
      // Logged out in another tab, or the session could not be refreshed.
      if (event === 'SIGNED_OUT' && mode === 'required' && !signingOut) {
        window.location.replace(loginUrl(currentPagePath()));
      }
      if (session && (event === 'USER_UPDATED' || event === 'TOKEN_REFRESHED')) {
        fillUser(session.user);
      }
    });
  }

  /* ---------------------------------------------------------------------------
   * Form helpers for the auth pages
   * Errors use the existing markup: a .field__error <p> named in the input's
   * aria-describedby, and a role="alert" banner at the top of the form.
   * ------------------------------------------------------------------------- */

  var EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

  function fieldErrorElement(input) {
    var ids = (input.getAttribute('aria-describedby') || '').split(/\s+/);
    for (var i = 0; i < ids.length; i++) {
      var el = ids[i] && document.getElementById(ids[i]);
      if (el && el.classList.contains('field__error')) return el;
    }
    return null;
  }

  function setFieldError(input, message) {
    var errorEl = fieldErrorElement(input);
    if (message) {
      input.setAttribute('aria-invalid', 'true');
      if (errorEl) {
        errorEl.textContent = message;
        errorEl.hidden = false;
      }
    } else {
      input.removeAttribute('aria-invalid');
      if (errorEl) errorEl.hidden = true;
    }
  }

  function showAlert(alertEl, message) {
    if (!alertEl) return;
    alertEl.textContent = message || '';
    alertEl.hidden = !message;
  }

  function clearErrors(form, alertEl) {
    form.querySelectorAll('[aria-invalid="true"]').forEach(function (input) {
      setFieldError(input, null);
    });
    showAlert(alertEl, null);
  }

  // Disables the submit button and swaps its label while a request runs.
  function setBusy(form, busy, busyLabel) {
    var button = form.querySelector('[type="submit"]');
    if (!button) return;
    if (busy) {
      button.dataset.label = button.textContent;
      button.textContent = busyLabel;
      button.disabled = true;
      form.setAttribute('aria-busy', 'true');
    } else {
      if (button.dataset.label) button.textContent = button.dataset.label;
      button.disabled = false;
      form.removeAttribute('aria-busy');
    }
  }

  // Turns a Supabase Auth error into a sentence for the user.
  function errorMessage(error) {
    if (!error) return '';
    var code = error.code || '';
    var message = (error.message || '').toLowerCase();

    if (error.name === 'AuthRetryableFetchError' || message.indexOf('failed to fetch') !== -1) {
      return "We can't reach the server. Check your connection and try again.";
    }
    if (error.status === 429 || code.indexOf('rate_limit') !== -1 || message.indexOf('rate limit') !== -1) {
      return 'Too many attempts. Wait a few minutes and try again.';
    }
    if (code === 'email_not_confirmed' || message.indexOf('email not confirmed') !== -1) {
      return 'Confirm your email first. Open the link we sent you, then log in.';
    }
    if (code === 'invalid_credentials' || message.indexOf('invalid login credentials') !== -1) {
      return "That email and password don't match. Try again or reset your password.";
    }
    if (code === 'user_already_exists' || code === 'email_exists' || message.indexOf('already registered') !== -1) {
      return 'An account with that email already exists. Try logging in instead.';
    }
    if (code === 'weak_password' || message.indexOf('password should') !== -1) {
      return error.message;
    }
    if (code === 'same_password') {
      return 'Choose a password different from your current one.';
    }
    return error.message || 'Something went wrong. Please try again.';
  }

  /* ---------------------------------------------------------------------------
   * Public API
   * ------------------------------------------------------------------------- */

  window.TradeLab.auth = {
    ready: ready,
    getUser: getUser,
    signOut: signOut,
    siteUrl: siteUrl,
    nextUrl: nextUrl,
    errorMessage: errorMessage,
    form: {
      isEmail: function (value) { return EMAIL_PATTERN.test(value); },
      setFieldError: setFieldError,
      showAlert: showAlert,
      clearErrors: clearErrors,
      setBusy: setBusy
    }
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initSignOut);
  } else {
    initSignOut();
  }
})();
