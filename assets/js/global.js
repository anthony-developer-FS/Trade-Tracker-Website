/**
 * TradeLab global UI behavior, loaded on every page.
 *
 * Only shared interface behavior lives here: night mode, the mobile menu,
 * dropdown menus, the header shadow and small helpers. Page features (forms, charts, data)
 * belong in their own files under assets/js/pages/, and data access in its
 * own module, so this file never needs to know about trades.
 *
 * Load it in <head> without defer so the saved theme is set before the page
 * paints (no light flash in night mode). Everything else waits for the DOM.
 *
 * Markup hooks (see assets/css/components/navigation.css):
 *   <html data-theme-lock="light">  page that ignores night mode (landing)
 *   [data-theme-toggle]        night mode button (aria-pressed = dark is on)
 *   [data-nav-toggle]          button with aria-controls="<nav id>"
 *   [data-dropdown]            wrapper with [data-dropdown-trigger] and
 *                              [data-dropdown-menu] inside
 *   [data-elevate-on-scroll]   header that gets .is-scrolled after scrolling
 *   [data-password-toggle]     Show/Hide button for the input in aria-controls
 *   [data-current-year]        element whose text becomes the current year
 */
(function () {
  'use strict';

  // Must match the max-width breakpoint in navigation.css.
  var MOBILE_NAV_QUERY = window.matchMedia('(max-width: 860px)');
  var DARK_SCHEME_QUERY = window.matchMedia('(prefers-color-scheme: dark)');
  var THEME_STORAGE_KEY = 'tradelab-theme';
  var root = document.documentElement;

  /* ---------------------------------------------------------------------------
   * Night mode
   * The theme is <html data-theme="light|dark">; the dark color tokens live in
   * the theme file. A saved choice wins, otherwise the system setting is used.
   * ------------------------------------------------------------------------- */

  function savedTheme() {
    try {
      var theme = window.localStorage.getItem(THEME_STORAGE_KEY);
      return theme === 'light' || theme === 'dark' ? theme : null;
    } catch (error) {
      return null; // storage blocked (private mode, strict settings)
    }
  }

  function saveTheme(theme) {
    try {
      window.localStorage.setItem(THEME_STORAGE_KEY, theme);
    } catch (error) {
      // The choice still applies to this page; it just won't be remembered.
    }
  }

  function currentTheme() {
    return root.getAttribute('data-theme') === 'dark' ? 'dark' : 'light';
  }

  function applyTheme(theme) {
    if (root.hasAttribute('data-theme-lock')) {
      theme = root.getAttribute('data-theme-lock');
    }
    root.setAttribute('data-theme', theme);
    document.querySelectorAll('[data-theme-toggle]').forEach(function (toggle) {
      toggle.setAttribute('aria-pressed', String(theme === 'dark'));
    });
  }

  function setTheme(theme) {
    saveTheme(theme);
    applyTheme(theme);
  }

  // Runs immediately (not on DOMContentLoaded) so there is no flash.
  applyTheme(savedTheme() || (DARK_SCHEME_QUERY.matches ? 'dark' : 'light'));

  function initThemeToggles() {
    applyTheme(currentTheme()); // sync aria-pressed now that buttons exist

    document.querySelectorAll('[data-theme-toggle]').forEach(function (toggle) {
      toggle.addEventListener('click', function () {
        setTheme(currentTheme() === 'dark' ? 'light' : 'dark');
      });
    });

    // Follow the system setting until the visitor picks a theme themselves.
    DARK_SCHEME_QUERY.addEventListener('change', function (event) {
      if (!savedTheme()) applyTheme(event.matches ? 'dark' : 'light');
    });

    // Keep other open tabs in step.
    window.addEventListener('storage', function (event) {
      if (event.key === THEME_STORAGE_KEY && savedTheme()) applyTheme(savedTheme());
    });
  }

  /* ---------------------------------------------------------------------------
   * Mobile navigation
   * ------------------------------------------------------------------------- */

  function setNavOpen(toggle, open) {
    var nav = document.getElementById(toggle.getAttribute('aria-controls'));
    if (!nav) return;

    toggle.setAttribute('aria-expanded', String(open));
    toggle.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
    nav.classList.toggle('is-open', open);
    document.body.classList.toggle('is-scroll-locked', open);

    if (open) {
      var firstLink = nav.querySelector('a, button');
      if (firstLink) firstLink.focus();
    }
  }

  function closeAllNavs(returnFocus) {
    document.querySelectorAll('[data-nav-toggle][aria-expanded="true"]').forEach(function (toggle) {
      setNavOpen(toggle, false);
      if (returnFocus) toggle.focus();
    });
  }

  function initNavToggles() {
    document.querySelectorAll('[data-nav-toggle]').forEach(function (toggle) {
      var nav = document.getElementById(toggle.getAttribute('aria-controls'));
      if (!nav) return;

      toggle.addEventListener('click', function () {
        setNavOpen(toggle, toggle.getAttribute('aria-expanded') !== 'true');
      });

      // Following a link (including #anchors on the same page) closes the menu.
      nav.addEventListener('click', function (event) {
        if (event.target.closest('a')) setNavOpen(toggle, false);
      });
    });

    // Leaving the mobile layout resets the menu so desktop never inherits it.
    MOBILE_NAV_QUERY.addEventListener('change', function (event) {
      if (!event.matches) closeAllNavs(false);
    });
  }

  /* ---------------------------------------------------------------------------
   * Dropdown menus (disclosure pattern)
   * ------------------------------------------------------------------------- */

  function setDropdownOpen(dropdown, open) {
    var trigger = dropdown.querySelector('[data-dropdown-trigger]');
    var menu = dropdown.querySelector('[data-dropdown-menu]');
    if (!trigger || !menu) return;

    trigger.setAttribute('aria-expanded', String(open));
    menu.hidden = !open;
  }

  function closeAllDropdowns(except) {
    document.querySelectorAll('[data-dropdown]').forEach(function (dropdown) {
      if (dropdown !== except) setDropdownOpen(dropdown, false);
    });
  }

  function menuItems(dropdown) {
    return Array.prototype.slice.call(
      dropdown.querySelectorAll('[data-dropdown-menu] a, [data-dropdown-menu] button')
    );
  }

  function initDropdowns() {
    document.querySelectorAll('[data-dropdown]').forEach(function (dropdown) {
      var trigger = dropdown.querySelector('[data-dropdown-trigger]');
      if (!trigger) return;

      trigger.addEventListener('click', function () {
        var open = trigger.getAttribute('aria-expanded') !== 'true';
        closeAllDropdowns(dropdown);
        setDropdownOpen(dropdown, open);
      });

      // Arrow keys move between items; Down on the trigger opens the menu.
      dropdown.addEventListener('keydown', function (event) {
        if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp') return;

        var items = menuItems(dropdown);
        if (!items.length) return;
        event.preventDefault();

        if (event.target === trigger) {
          setDropdownOpen(dropdown, true);
          items[0].focus();
          return;
        }

        var index = items.indexOf(document.activeElement);
        var next = event.key === 'ArrowDown' ? index + 1 : index - 1;
        items[(next + items.length) % items.length].focus();
      });

      // Tabbing out of the menu closes it.
      dropdown.addEventListener('focusout', function (event) {
        if (!dropdown.contains(event.relatedTarget)) setDropdownOpen(dropdown, false);
      });
    });

    // Clicking anywhere outside an open dropdown closes it.
    document.addEventListener('click', function (event) {
      if (!event.target.closest('[data-dropdown]')) closeAllDropdowns(null);
    });
  }

  /* ---------------------------------------------------------------------------
   * Escape closes whatever is open, innermost first.
   * ------------------------------------------------------------------------- */

  function initEscapeKey() {
    document.addEventListener('keydown', function (event) {
      if (event.key !== 'Escape') return;

      var openDropdown = document.querySelector('[data-dropdown] [data-dropdown-trigger][aria-expanded="true"]');
      if (openDropdown) {
        closeAllDropdowns(null);
        openDropdown.focus();
        return;
      }

      closeAllNavs(true);
    });
  }

  /* ---------------------------------------------------------------------------
   * Header shadow once the page has scrolled
   * ------------------------------------------------------------------------- */

  function initHeaderElevation() {
    var header = document.querySelector('[data-elevate-on-scroll]');
    if (!header) return;

    var ticking = false;
    function update() {
      header.classList.toggle('is-scrolled', window.scrollY > 4);
      ticking = false;
    }

    window.addEventListener('scroll', function () {
      if (!ticking) {
        window.requestAnimationFrame(update);
        ticking = true;
      }
    }, { passive: true });

    update();
  }

  /* ---------------------------------------------------------------------------
   * Small helpers
   * ------------------------------------------------------------------------- */

  function initCurrentYear() {
    var year = String(new Date().getFullYear());
    document.querySelectorAll('[data-current-year]').forEach(function (el) {
      el.textContent = year;
    });
  }

  // Show/Hide button on password inputs ([data-password-toggle] with
  // aria-controls pointing at the input).
  function initPasswordToggles() {
    document.querySelectorAll('[data-password-toggle]').forEach(function (button) {
      var input = document.getElementById(button.getAttribute('aria-controls'));
      if (!input) return;

      button.addEventListener('click', function () {
        var show = input.type === 'password';
        input.type = show ? 'text' : 'password';
        button.setAttribute('aria-pressed', String(show));
        button.textContent = show ? 'Hide' : 'Show';
      });
    });
  }

  function init() {
    initThemeToggles();
    initNavToggles();
    initDropdowns();
    initEscapeKey();
    initHeaderElevation();
    initPasswordToggles();
    initCurrentYear();
  }

  // Shared API for page scripts, e.g. TradeLab.ui.closeMenus() before a modal
  // opens, or TradeLab.ui.setTheme('dark') from a settings page.
  window.TradeLab = window.TradeLab || {};
  window.TradeLab.ui = {
    closeMenus: function () {
      closeAllDropdowns(null);
      closeAllNavs(false);
    },
    getTheme: currentTheme,
    setTheme: setTheme
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
