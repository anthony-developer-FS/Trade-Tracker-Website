/**
 * Choose a new password. The reset email links here; supabase-js reads the
 * recovery token from the URL and signs the user in, then updateUser sets
 * the new password. Without a valid link, the page says so and offers a new
 * one.
 */
(function () {
  'use strict';

  var auth = window.TradeLab.auth;
  var supabase = window.TradeLab.supabase;
  var helpers = auth.form;

  var form = document.getElementById('new-password-form');
  var alertEl = document.getElementById('new-password-error');
  var invalid = document.getElementById('new-password-invalid');
  var done = document.getElementById('new-password-done');
  var passwordInput = document.getElementById('new-password');
  var confirmInput = document.getElementById('new-password-confirm');
  if (!form) return;

  function showOnly(el) {
    [form, invalid, done].forEach(function (section) { section.hidden = section !== el; });
    if (el !== form) {
      el.setAttribute('tabindex', '-1');
      el.focus();
    }
  }

  if (!supabase) {
    helpers.showAlert(alertEl, window.TradeLab.supabaseError);
    return;
  }

  // An expired or already used link comes back with the error in the URL.
  var hash = new URLSearchParams(window.location.hash.slice(1));
  var query = new URLSearchParams(window.location.search);
  if (hash.get('error') || query.get('error')) {
    showOnly(invalid);
    return;
  }

  auth.ready.then(function (user) {
    if (!user) showOnly(invalid);
  });

  form.addEventListener('submit', function (event) {
    event.preventDefault();
    helpers.clearErrors(form, alertEl);

    var ok = true;
    if (passwordInput.value.length < 8) {
      helpers.setFieldError(passwordInput, 'Use at least 8 characters.');
      ok = false;
    }
    if (confirmInput.value !== passwordInput.value) {
      helpers.setFieldError(confirmInput, "The passwords don't match.");
      ok = false;
    }
    if (!ok) {
      form.querySelector('[aria-invalid="true"]').focus();
      return;
    }

    helpers.setBusy(form, true, 'Saving…');

    supabase.auth.updateUser({ password: passwordInput.value }).then(function (result) {
      if (result.error) throw result.error;
      showOnly(done);
    }).catch(function (error) {
      helpers.setBusy(form, false);
      helpers.showAlert(alertEl, auth.errorMessage(error));
    });
  });
})();
