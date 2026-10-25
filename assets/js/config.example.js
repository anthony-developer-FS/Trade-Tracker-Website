/**
 * TradeLab settings for connecting to Supabase.
 *
 * Copy this file to assets/js/config.js and fill in your project's values from
 * the Supabase dashboard (Project Settings > API, or the Connect button):
 *
 *   cp assets/js/config.example.js assets/js/config.js
 *
 * config.js is gitignored, so your values stay out of the repo.
 *
 * Use the anon (or "publishable") key here. It is safe in the browser because
 * row level security decides what each user can see. Never put the
 * service_role (or "secret") key in this file or anywhere in the front end.
 */
window.TRADELAB_CONFIG = {
  supabaseUrl: 'https://YOUR-PROJECT-REF.supabase.co',
  supabaseAnonKey: 'YOUR-ANON-OR-PUBLISHABLE-KEY'
};
