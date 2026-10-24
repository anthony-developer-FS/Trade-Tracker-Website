-- =============================================================================
-- Core tables: users, broker accounts, instruments, trades and fills,
-- and the ways users organize trades (lists, setups, tags, journal).
--
-- Conventions used throughout:
--   * Every user-owned row has user_id (defaults to the signed-in user).
--   * Child tables point at their parent with (parent_id, user_id) composite
--     foreign keys, so a row can never link to another user's data.
--   * Every table has a metadata jsonb column for fields that are not worth a
--     real column yet. Promote a key to a column once the app depends on it.
-- =============================================================================

create type public.trade_direction as enum ('long', 'short');
create type public.trade_status    as enum ('open', 'closed');
create type public.execution_side  as enum ('buy', 'sell');

-- -----------------------------------------------------------------------------
-- Profiles: one row per auth user, created by a trigger on sign-up.
-- -----------------------------------------------------------------------------
create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text check (char_length(display_name) <= 80),
  username      text check (username ~ '^[A-Za-z0-9_]{3,30}$'),
  avatar_url    text,
  timezone      text not null default 'America/New_York',
  base_currency text not null default 'USD',
  plan_id       text not null default 'free' references public.plans (id),
  preferences   jsonb not null default '{}'::jsonb,
  metadata      jsonb not null default '{}'::jsonb,
  onboarded_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create unique index profiles_username_key on public.profiles (lower(username));

comment on column public.profiles.timezone is 'IANA time zone used to bucket trades into days for calendars and charts.';
comment on column public.profiles.plan_id  is 'Current plan. Written only by the server (billing webhook), never by the client.';

-- -----------------------------------------------------------------------------
-- Subscriptions: billing history. Unused until paid plans launch.
-- -----------------------------------------------------------------------------
create table public.subscriptions (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid not null references public.profiles (id) on delete cascade,
  plan_id                  text not null references public.plans (id),
  status                   text not null check (status in ('trialing', 'active', 'past_due', 'canceled', 'incomplete')),
  provider                 text not null default 'stripe',
  provider_customer_id     text,
  provider_subscription_id text unique,
  current_period_start     timestamptz,
  current_period_end       timestamptz,
  cancel_at                timestamptz,
  canceled_at              timestamptz,
  metadata                 jsonb not null default '{}'::jsonb,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

create index subscriptions_user_id_idx on public.subscriptions (user_id);

-- -----------------------------------------------------------------------------
-- Broker accounts: the user's real accounts, e.g. "Schwab IRA".
-- -----------------------------------------------------------------------------
create table public.broker_accounts (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  broker_id        text not null references public.brokers (id),
  name             text not null check (char_length(btrim(name)) between 1 and 60),
  account_last4    text check (account_last4 ~ '^[A-Za-z0-9]{1,4}$'),
  currency         text not null default 'USD',
  is_paper         boolean not null default false,
  starting_balance numeric,
  is_archived      boolean not null default false,
  metadata         jsonb not null default '{}'::jsonb,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (id, user_id)
);

create unique index broker_accounts_user_name_key on public.broker_accounts (user_id, lower(name));

comment on column public.broker_accounts.account_last4 is 'Only the last 4 characters. Full account numbers are never stored.';

-- -----------------------------------------------------------------------------
-- Instruments: shared catalog of tradable things, one row per contract.
-- Created only through public.get_or_create_instrument().
-- -----------------------------------------------------------------------------
create table public.instruments (
  id                uuid primary key default gen_random_uuid(),
  asset_class       text not null references public.asset_classes (id),
  symbol            text not null,
  underlying_symbol text not null,
  option_type       text check (option_type in ('call', 'put')),
  strike            numeric check (strike > 0),
  expiration_date   date,
  multiplier        numeric not null default 1 check (multiplier > 0),
  quote_currency    text not null default 'USD',
  exchange          text,
  metadata          jsonb not null default '{}'::jsonb,
  created_at        timestamptz not null default now(),
  unique (asset_class, symbol),
  constraint instruments_option_fields check (
    asset_class <> 'option'
    or (option_type is not null and strike is not null and expiration_date is not null)
  )
);

create index instruments_underlying_idx on public.instruments (underlying_symbol);

comment on column public.instruments.symbol is
  'Canonical symbol: AAPL (stock), OCC symbol e.g. AAPL  261218C00150000 (option), ESZ6 (future), BTC-USD (crypto).';
comment on column public.instruments.underlying_symbol is
  'What analytics group by: AAPL for AAPL options, ES for every ES contract month, BTC for BTC-USD.';

-- -----------------------------------------------------------------------------
-- Setups: the user's named strategies or playbook plays (one per trade).
-- -----------------------------------------------------------------------------
create table public.setups (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 60),
  description text,
  color       text,
  rules       jsonb not null default '[]'::jsonb,
  is_archived boolean not null default false,
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (id, user_id)
);

create unique index setups_user_name_key on public.setups (user_id, lower(name));

-- -----------------------------------------------------------------------------
-- Tags: free-form labels, many per trade (mistakes, emotions, conditions).
-- -----------------------------------------------------------------------------
create table public.tags (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 1 and 40),
  category   text not null default 'general',
  color      text,
  created_at timestamptz not null default now(),
  unique (id, user_id)
);

create unique index tags_user_name_key on public.tags (user_id, lower(name));

-- -----------------------------------------------------------------------------
-- Trade lists: user-named groups such as "Schwab options" or "Swing trades".
-- The number a user can create comes from their plan (limits.max_trade_lists).
-- -----------------------------------------------------------------------------
create table public.trade_lists (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 60),
  description text,
  color       text,
  icon        text,
  sort_order  integer not null default 0,
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (id, user_id)
);

create unique index trade_lists_user_name_key on public.trade_lists (user_id, lower(name));

-- -----------------------------------------------------------------------------
-- Trades: one round trip in one instrument (open -> close). The numbers
-- (quantity, prices, P&L, status, times) are calculated from executions by a
-- trigger and cannot be written by the client.
-- -----------------------------------------------------------------------------
create table public.trades (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  broker_account_id uuid,
  instrument_id     uuid not null references public.instruments (id),
  asset_class       text not null references public.asset_classes (id),
  direction         public.trade_direction not null,
  status            public.trade_status not null default 'open',

  -- Calculated from executions
  opened_at         timestamptz,
  closed_at         timestamptz,
  quantity          numeric not null default 0,
  avg_entry_price   numeric,
  avg_exit_price    numeric,
  gross_pnl         numeric not null default 0,
  fees              numeric not null default 0,
  net_pnl           numeric not null default 0,
  execution_count   integer not null default 0,

  -- Entered by the user
  setup_id          uuid,
  planned_risk      numeric check (planned_risk > 0),
  stop_price        numeric,
  target_price      numeric,
  rating            smallint check (rating between 1 and 5),
  notes             text,

  source            text not null default 'manual' check (source in ('manual', 'import', 'api')),
  import_id         uuid,
  metadata          jsonb not null default '{}'::jsonb,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  r_multiple        numeric generated always as (
                      case when planned_risk > 0 then round(net_pnl / planned_risk, 4) end
                    ) stored,
  hold_seconds      numeric generated always as (
                      extract(epoch from (closed_at - opened_at))
                    ) stored,

  unique (id, user_id),
  foreign key (broker_account_id, user_id)
    references public.broker_accounts (id, user_id) on delete set null (broker_account_id),
  foreign key (setup_id, user_id)
    references public.setups (id, user_id) on delete set null (setup_id)
);

comment on column public.trades.asset_class is 'Copied from the instrument by a trigger so each market tab can filter quickly.';
comment on column public.trades.planned_risk is 'Dollars at risk when the trade was planned. Enables R-multiple stats.';

create index trades_user_closed_idx       on public.trades (user_id, closed_at desc);
create index trades_user_asset_closed_idx on public.trades (user_id, asset_class, closed_at desc);
create index trades_user_status_idx       on public.trades (user_id, status);
create index trades_broker_account_idx    on public.trades (broker_account_id);
create index trades_instrument_idx        on public.trades (instrument_id);
create index trades_setup_idx             on public.trades (setup_id);

-- -----------------------------------------------------------------------------
-- Executions: individual fills. The source of truth for every trade number.
-- -----------------------------------------------------------------------------
create table public.executions (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  trade_id            uuid not null,
  side                public.execution_side not null,
  position_effect     text not null default 'unknown' check (position_effect in ('open', 'close', 'unknown')),
  quantity            numeric not null check (quantity > 0),
  price               numeric not null check (price >= 0),
  commission          numeric not null default 0,
  fees                numeric not null default 0,
  executed_at         timestamptz not null,
  broker_execution_id text,
  dedupe_key          text,
  import_id           uuid,
  metadata            jsonb not null default '{}'::jsonb,
  created_at          timestamptz not null default now(),
  foreign key (trade_id, user_id) references public.trades (id, user_id) on delete cascade
);

comment on column public.executions.dedupe_key is
  'Stable key per fill (broker execution id, or a hash of the row) so re-importing the same file never duplicates trades.';

create index executions_trade_idx on public.executions (trade_id, executed_at);
create index executions_user_time_idx on public.executions (user_id, executed_at);
create unique index executions_user_dedupe_key on public.executions (user_id, dedupe_key) where dedupe_key is not null;

-- -----------------------------------------------------------------------------
-- Join tables
-- -----------------------------------------------------------------------------
create table public.trade_list_items (
  trade_list_id uuid not null,
  trade_id      uuid not null,
  user_id       uuid not null default auth.uid(),
  added_at      timestamptz not null default now(),
  primary key (trade_list_id, trade_id),
  foreign key (trade_list_id, user_id) references public.trade_lists (id, user_id) on delete cascade,
  foreign key (trade_id, user_id)      references public.trades (id, user_id)      on delete cascade
);

create index trade_list_items_trade_idx on public.trade_list_items (trade_id);

create table public.trade_tags (
  trade_id uuid not null,
  tag_id   uuid not null,
  user_id  uuid not null default auth.uid(),
  primary key (trade_id, tag_id),
  foreign key (trade_id, user_id) references public.trades (id, user_id) on delete cascade,
  foreign key (tag_id, user_id)   references public.tags (id, user_id)   on delete cascade
);

create index trade_tags_tag_idx on public.trade_tags (tag_id);

-- -----------------------------------------------------------------------------
-- Journal and screenshots
-- -----------------------------------------------------------------------------
create table public.journal_entries (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  entry_date date not null,
  title      text,
  body       text,
  mood       smallint check (mood between 1 and 5),
  metadata   jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index journal_entries_user_date_idx on public.journal_entries (user_id, entry_date desc);

create table public.trade_attachments (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid(),
  trade_id     uuid not null,
  storage_path text not null unique,
  file_name    text,
  mime_type    text,
  size_bytes   bigint check (size_bytes >= 0),
  caption      text,
  created_at   timestamptz not null default now(),
  foreign key (trade_id, user_id) references public.trades (id, user_id) on delete cascade
);

create index trade_attachments_trade_idx on public.trade_attachments (trade_id);

-- -----------------------------------------------------------------------------
-- updated_at triggers
-- -----------------------------------------------------------------------------
create trigger profiles_set_updated_at        before update on public.profiles        for each row execute function public.set_updated_at();
create trigger subscriptions_set_updated_at   before update on public.subscriptions   for each row execute function public.set_updated_at();
create trigger broker_accounts_set_updated_at before update on public.broker_accounts for each row execute function public.set_updated_at();
create trigger setups_set_updated_at          before update on public.setups          for each row execute function public.set_updated_at();
create trigger trade_lists_set_updated_at     before update on public.trade_lists     for each row execute function public.set_updated_at();
create trigger trades_set_updated_at          before update on public.trades          for each row execute function public.set_updated_at();
create trigger journal_entries_set_updated_at before update on public.journal_entries for each row execute function public.set_updated_at();
