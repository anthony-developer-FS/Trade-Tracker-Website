/**
 * Log in page: email and password sign-in with Supabase Auth.
 * After logging in, the user goes to ?next= (set by the page guard) or the
 * trade log.
 */
(function () {
  'use strict';

  var auth = window.TradeLab.auth;
  var supabase = window.TradeLab.supabase;
  var helpers = auth.form;

  var form = document.getElementById('login-form');
  var alertEl = document.getElementById('login-error');
  var emailInput = document.getElementById('login-email');
  var passwordInput = document.getElementById('login-password');
  if (!form) return;

  if (!supabase) helpers.showAlert(alertEl, window.TradeLab.supabaseError);

  function validate() {
    var ok = true;
    if (!helpers.isEmail(emailInput.value.trim())) {
      helpers.setFieldError(emailInput, 'Enter a valid email address.');
      ok = false;
    }
    if (!passwordInput.value) {
      helpers.setFieldError(passwordInput, 'Enter your password.');
      ok = false;
    }
    return ok;
  }

  form.addEventListener('submit', function (event) {
    event.preventDefault();
    helpers.clearErrors(form, alertEl);

    if (!supabase) {
      helpers.showAlert(alertEl, window.TradeLab.supabaseError);
      return;
    }
    if (!validate()) {
      form.querySelector('[aria-invalid="true"]').focus();
      return;
    }

    window.TradeLab.setRememberMe(form.elements.remember ? form.elements.remember.checked : true);
    helpers.setBusy(form, true, 'Logging in…');

    supabase.auth.signInWithPassword({
      email: emailInput.value.trim(),
      password: passwordInput.value
    }).then(function (result) {
      if (result.error) throw result.error;
      window.location.assign(auth.nextUrl());
    }).catch(function (error) {
      helpers.setBusy(form, false);
      helpers.showAlert(alertEl, auth.errorMessage(error));
      passwordInput.select();
    });
  });
})();
