-- =============================================================================
-- Foundation: shared helpers and reference (lookup) tables.
--
-- Reference tables use readable text primary keys ('stock', 'schwab', 'free').
-- New markets, brokers or plans are added later with a plain INSERT, not a
-- schema change.
-- =============================================================================

-- Keeps updated_at current on every UPDATE.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Plans. Paid plans are seeded but inactive while the product is free.
-- -----------------------------------------------------------------------------
create table public.plans (
  id                  text primary key,
  name                text not null,
  description         text,
  price_monthly_cents integer check (price_monthly_cents >= 0),
  price_yearly_cents  integer check (price_yearly_cents >= 0),
  limits              jsonb not null default '{}'::jsonb,
  features            jsonb not null default '[]'::jsonb,
  is_active           boolean not null default true,
  is_public           boolean not null default true,
  sort_order          integer not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

comment on column public.plans.limits is
  'Usage limits by name, e.g. {"max_trade_lists": 2}. A missing key or null value means unlimited.';

create trigger plans_set_updated_at
  before update on public.plans
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Markets. Each one gets its own tab and analytics in the app.
-- -----------------------------------------------------------------------------
create table public.asset_classes (
  id                 text primary key,
  name               text not null,
  default_multiplier numeric not null default 1 check (default_multiplier > 0),
  is_active          boolean not null default true,
  sort_order         integer not null default 0
);

comment on column public.asset_classes.default_multiplier is
  'Contract multiplier used when an instrument does not specify one (100 for US equity options).';

-- -----------------------------------------------------------------------------
-- Brokers we support importing from.
-- -----------------------------------------------------------------------------
create table public.brokers (
  id               text primary key,
  name             text not null,
  website          text,
  asset_classes    text[] not null default '{}',
  import_supported boolean not null default false,
  is_active        boolean not null default true,
  sort_order       integer not null default 0,
  metadata         jsonb not null default '{}'::jsonb
);

-- -----------------------------------------------------------------------------
-- Futures contract specs. Futures exports (Tradovate, NinjaTrader) often omit
-- the point value, so P&L needs this table to be correct.
-- -----------------------------------------------------------------------------
create table public.futures_specs (
  root_symbol text primary key,
  name        text not null,
  exchange    text,
  multiplier  numeric not null check (multiplier > 0),
  tick_size   numeric not null check (tick_size > 0),
  tick_value  numeric generated always as (multiplier * tick_size) stored,
  currency    text not null default 'USD',
  is_active   boolean not null default true
);

comment on column public.futures_specs.multiplier is 'Dollar value of a 1.0 point move for one contract.';

-- -----------------------------------------------------------------------------
-- Reference data
-- -----------------------------------------------------------------------------
insert into public.plans (id, name, description, limits, is_active, is_public, sort_order) values
  ('free',  'Free',  'Everything included during the launch period.', '{"max_trade_lists": 2}', true,  true, 0),
  ('basic', 'Basic', 'Paid plan. Pricing to be decided.',              '{"max_trade_lists": 2}', false, true, 1),
  ('pro',   'Pro',   'Paid plan. Pricing to be decided.',              '{"max_trade_lists": 2}', false, true, 2);

insert into public.asset_classes (id, name, default_multiplier, sort_order) values
  ('stock',  'Stocks',  1,   0),
  ('option', 'Options', 100, 1),
  ('future', 'Futures', 1,   2),
  ('crypto', 'Crypto',  1,   3);

insert into public.brokers (id, name, website, asset_classes, import_supported, sort_order) values
  ('schwab',              'Charles Schwab / thinkorswim', 'https://www.schwab.com',            '{stock,option,future}',        true, 0),
  ('fidelity',            'Fidelity',                     'https://www.fidelity.com',          '{stock,option,crypto}',        true, 1),
  ('robinhood',           'Robinhood',                    'https://robinhood.com',             '{stock,option,future,crypto}', true, 2),
  ('interactive_brokers', 'Interactive Brokers',          'https://www.interactivebrokers.com','{stock,option,future,crypto}', true, 3),
  ('webull',              'Webull',                       'https://www.webull.com',            '{stock,option,future,crypto}', true, 4),
  ('tradovate',           'Tradovate',                    'https://www.tradovate.com',         '{future}',                     true, 5),
  ('ninjatrader',         'NinjaTrader',                  'https://ninjatrader.com',           '{future}',                     true, 6),
  ('other',               'Other / generic CSV',          null,                                '{stock,option,future,crypto}', true, 99);

insert into public.futures_specs (root_symbol, name, exchange, multiplier, tick_size) values
  ('ES',  'E-mini S&P 500',          'CME',   50,     0.25),
  ('MES', 'Micro E-mini S&P 500',    'CME',   5,      0.25),
  ('NQ',  'E-mini Nasdaq-100',       'CME',   20,     0.25),
  ('MNQ', 'Micro E-mini Nasdaq-100', 'CME',   2,      0.25),
  ('YM',  'E-mini Dow',              'CBOT',  5,      1),
  ('MYM', 'Micro E-mini Dow',        'CBOT',  0.5,    1),
  ('RTY', 'E-mini Russell 2000',     'CME',   50,     0.1),
  ('M2K', 'Micro E-mini Russell 2000','CME',  5,      0.1),
  ('CL',  'Crude Oil',               'NYMEX', 1000,   0.01),
  ('MCL', 'Micro Crude Oil',         'NYMEX', 100,    0.01),
  ('NG',  'Natural Gas',             'NYMEX', 10000,  0.001),
  ('GC',  'Gold',                    'COMEX', 100,    0.1),
  ('MGC', 'Micro Gold',              'COMEX', 10,     0.1),
  ('SI',  'Silver',                  'COMEX', 5000,   0.005),
  ('ZB',  '30-Year T-Bond',          'CBOT',  1000,   0.03125),
  ('ZN',  '10-Year T-Note',          'CBOT',  1000,   0.015625),
  ('6E',  'Euro FX',                 'CME',   125000, 0.00005);
