/**
 * Sign up page: creates the account with Supabase Auth.
 * full_name is copied into profiles.display_name by the database
 * (handle_new_user trigger).
 *
 * With email confirmation on (the Supabase default) the form is replaced by
 * "Check your email". With it off, the user is signed in and goes straight
 * to the trade log.
 */
(function () {
  'use strict';

  var auth = window.TradeLab.auth;
  var supabase = window.TradeLab.supabase;
  var helpers = auth.form;

  var form = document.getElementById('signup-form');
  var alertEl = document.getElementById('signup-error');
  var success = document.getElementById('signup-success');
  var nameInput = document.getElementById('signup-name');
  var emailInput = document.getElementById('signup-email');
  var passwordInput = document.getElementById('signup-password');
  var termsInput = form ? form.elements.accept_terms : null;
  if (!form) return;

  if (!supabase) helpers.showAlert(alertEl, window.TradeLab.supabaseError);

  function validate() {
    var ok = true;
    if (!nameInput.value.trim()) {
      helpers.setFieldError(nameInput, 'Enter your name.');
      ok = false;
    }
    if (!helpers.isEmail(emailInput.value.trim())) {
      helpers.setFieldError(emailInput, 'Enter a valid email address.');
      ok = false;
    }
    if (passwordInput.value.length < 8) {
      helpers.setFieldError(passwordInput, 'Use at least 8 characters.');
      ok = false;
    }
    if (termsInput && !termsInput.checked) {
      termsInput.setAttribute('aria-invalid', 'true');
      if (ok) helpers.showAlert(alertEl, 'Please agree to the Terms of service and Privacy policy.');
      ok = false;
    }
    return ok;
  }

  function showSuccess(email) {
    success.querySelectorAll('[data-signup-email]').forEach(function (el) { el.textContent = email; });
    form.hidden = true;
    success.hidden = false;
    success.setAttribute('tabindex', '-1');
    success.focus();
  }

  form.addEventListener('submit', function (event) {
    event.preventDefault();
    helpers.clearErrors(form, alertEl);

    if (!supabase) {
      helpers.showAlert(alertEl, window.TradeLab.supabaseError);
      return;
    }
    if (!validate()) {
      var firstInvalid = form.querySelector('[aria-invalid="true"]');
      if (firstInvalid) firstInvalid.focus();
      return;
    }

    var email = emailInput.value.trim();
    helpers.setBusy(form, true, 'Creating account…');

    supabase.auth.signUp({
      email: email,
      password: passwordInput.value,
      options: {
        data: { full_name: nameInput.value.trim() },
        // Where the confirmation link lands. Must be in the Supabase
        // Redirect URLs list (Authentication > URL Configuration).
        emailRedirectTo: auth.siteUrl('app/trades.html')
      }
    }).then(function (result) {
      if (result.error) throw result.error;

      var data = result.data;
      // Email confirmation on and the address is already registered:
      // Supabase returns a user with no identities instead of an error.
      if (data.user && data.user.identities && data.user.identities.length === 0) {
        throw { code: 'user_already_exists' };
      }
      // Email confirmation off: already signed in.
      if (data.session) {
        window.location.assign(auth.siteUrl('app/trades.html'));
        return;
      }
      helpers.setBusy(form, false);
      showSuccess(email);
    }).catch(function (error) {
      helpers.setBusy(form, false);
      helpers.showAlert(alertEl, auth.errorMessage(error));
    });
  });
})();
