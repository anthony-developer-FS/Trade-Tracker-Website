/**
 * Forgot password page: emails a reset link. The link opens
 * reset-password.html, where the user chooses a new password.
 *
 * Supabase doesn't say whether the email has an account, so the page always
 * shows "Check your email" unless the request itself fails.
 */
(function () {
  'use strict';

  var auth = window.TradeLab.auth;
  var supabase = window.TradeLab.supabase;
  var helpers = auth.form;

  var form = document.getElementById('reset-form');
  var sent = document.getElementById('reset-sent');
  var emailInput = document.getElementById('reset-email');
  if (!form) return;

  // This page has no alert banner of its own, so errors go under the field.
  function showError(message) {
    helpers.setFieldError(emailInput, message);
    emailInput.focus();
  }

  if (!supabase) helpers.setFieldError(emailInput, window.TradeLab.supabaseError);

  form.addEventListener('submit', function (event) {
    event.preventDefault();
    helpers.clearErrors(form, null);

    if (!supabase) return showError(window.TradeLab.supabaseError);

    var email = emailInput.value.trim();
    if (!helpers.isEmail(email)) return showError('Enter a valid email address.');

    helpers.setBusy(form, true, 'Sending…');

    supabase.auth.resetPasswordForEmail(email, {
      // Must be in the Supabase Redirect URLs list.
      redirectTo: auth.siteUrl('reset-password.html')
    }).then(function (result) {
      if (result.error) throw result.error;
      form.hidden = true;
      sent.hidden = false;
      sent.setAttribute('tabindex', '-1');
      sent.focus();
    }).catch(function (error) {
      helpers.setBusy(form, false);
      showError(auth.errorMessage(error));
    });
  });
})();
