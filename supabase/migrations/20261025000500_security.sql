-- =============================================================================
-- Row level security and privileges.
--
-- Every user-owned table is visible and editable only by its owner.
-- Reference tables are read-only to clients. Calculated and billing columns
-- are writable only by the database itself or the service role.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Reference data: anyone can read, only the service role can change.
-- -----------------------------------------------------------------------------
alter table public.plans         enable row level security;
alter table public.asset_classes enable row level security;
alter table public.brokers       enable row level security;
alter table public.futures_specs enable row level security;
alter table public.instruments   enable row level security;

create policy "Plans are readable"         on public.plans         for select to anon, authenticated using (is_public);
create policy "Markets are readable"       on public.asset_classes for select to anon, authenticated using (true);
create policy "Brokers are readable"       on public.brokers       for select to anon, authenticated using (true);
create policy "Futures specs are readable" on public.futures_specs for select to anon, authenticated using (true);
create policy "Instruments are readable"   on public.instruments   for select to authenticated using (true);

revoke insert, update, delete, truncate on
  public.plans, public.asset_classes, public.brokers, public.futures_specs, public.instruments
  from anon, authenticated;

-- -----------------------------------------------------------------------------
-- Profiles: users read and edit their own; plan_id is server-only.
-- -----------------------------------------------------------------------------
alter table public.profiles enable row level security;

create policy "Users read own profile"   on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy "Users update own profile" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

revoke all on public.profiles from anon;
revoke insert, update, delete, truncate on public.profiles from authenticated;
grant update (display_name, username, avatar_url, timezone, base_currency, preferences, onboarded_at)
  on public.profiles to authenticated;

-- -----------------------------------------------------------------------------
-- Subscriptions: read-only to the owner, written by the billing webhook.
-- -----------------------------------------------------------------------------
alter table public.subscriptions enable row level security;

create policy "Users read own subscriptions" on public.subscriptions for select to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.subscriptions from anon;
revoke insert, update, delete, truncate on public.subscriptions from authenticated;

-- -----------------------------------------------------------------------------
-- User-owned tables: full access to your own rows, nothing else.
-- -----------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'broker_accounts', 'setups', 'tags', 'trade_lists', 'trades', 'executions',
    'trade_list_items', 'trade_tags', 'journal_entries', 'trade_attachments',
    'imports', 'import_rows'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    execute format(
      'create policy "Users read own rows" on public.%I for select to authenticated using (user_id = (select auth.uid()))', t);
    execute format(
      'create policy "Users insert own rows" on public.%I for insert to authenticated with check (user_id = (select auth.uid()))', t);
    execute format(
      'create policy "Users update own rows" on public.%I for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
    execute format(
      'create policy "Users delete own rows" on public.%I for delete to authenticated using (user_id = (select auth.uid()))', t);
  end loop;
end;
$$;

-- Trades: the calculated columns are maintained by recalculate_trade() only.
revoke insert, update on public.trades from authenticated;
grant insert (id, user_id, broker_account_id, instrument_id, direction, setup_id, planned_risk,
              stop_price, target_price, rating, notes, source, import_id, metadata)
  on public.trades to authenticated;
grant update (broker_account_id, instrument_id, direction, setup_id, planned_risk,
              stop_price, target_price, rating, notes, metadata)
  on public.trades to authenticated;

-- -----------------------------------------------------------------------------
-- Import templates: built-in ones (user_id null) are shared and read-only.
-- -----------------------------------------------------------------------------
alter table public.import_templates enable row level security;

create policy "Users read built-in and own templates" on public.import_templates for select to authenticated
  using (user_id is null or user_id = (select auth.uid()));
create policy "Users insert own templates" on public.import_templates for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Users update own templates" on public.import_templates for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "Users delete own templates" on public.import_templates for delete to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.import_templates from anon;
