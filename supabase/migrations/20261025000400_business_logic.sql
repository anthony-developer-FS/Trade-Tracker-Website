-- =============================================================================
-- Business rules enforced in the database, so every client (web app today,
-- Next.js or mobile later) gets the same numbers and limits.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- New users get a profile automatically.
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      split_part(new.email, '@', 1)
    ),
    new.raw_user_meta_data ->> 'avatar_url'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- -----------------------------------------------------------------------------
-- Plan limits. Returns null when the plan has no limit for that key.
-- -----------------------------------------------------------------------------
create or replace function public.plan_limit(p_user_id uuid, p_limit text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select (pl.limits ->> p_limit)::integer
  from public.profiles pr
  join public.plans pl on pl.id = pr.plan_id
  where pr.id = p_user_id;
$$;

revoke execute on function public.plan_limit(uuid, text) from public, anon, authenticated;

create or replace function public.enforce_trade_list_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit integer;
  v_count integer;
begin
  -- Serialize list creation per user so two tabs can't both slip under the limit.
  perform pg_advisory_xact_lock(hashtextextended('trade_lists:' || new.user_id::text, 0));

  v_limit := public.plan_limit(new.user_id, 'max_trade_lists');
  if v_limit is null then
    return new;
  end if;

  select count(*) into v_count from public.trade_lists where user_id = new.user_id;
  if v_count >= v_limit then
    raise exception 'Your plan allows up to % trade lists.', v_limit
      using errcode = 'P0001', hint = 'trade_list_limit_reached';
  end if;

  return new;
end;
$$;

create trigger trade_lists_enforce_limit
  before insert on public.trade_lists
  for each row execute function public.enforce_trade_list_limit();

-- -----------------------------------------------------------------------------
-- Instruments are shared across users, so they are created through this
-- function, which normalizes symbols and fills in the contract multiplier.
-- -----------------------------------------------------------------------------
create or replace function public.get_or_create_instrument(
  p_asset_class       text,
  p_symbol            text,
  p_underlying_symbol text    default null,
  p_option_type       text    default null,
  p_strike            numeric default null,
  p_expiration_date   date    default null,
  p_multiplier        numeric default null,
  p_quote_currency    text    default 'USD',
  p_exchange          text    default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_symbol      text := upper(btrim(p_symbol));
  v_underlying  text := upper(btrim(p_underlying_symbol));
  v_option_type text := lower(p_option_type);
  v_strike      numeric := p_strike;
  v_expiration  date := p_expiration_date;
  v_occ         text[];
  v_multiplier  numeric;
  v_id          uuid;
begin
  if auth.uid() is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;
  if v_symbol is null or v_symbol = '' then
    raise exception 'Symbol is required' using errcode = '22023';
  end if;

  -- Options: fill missing fields from an OCC symbol, then always store the
  -- canonical OCC symbol so "AAPL 261218C150" style variants can't duplicate.
  if p_asset_class = 'option' then
    v_occ := regexp_match(v_symbol, '^([A-Z0-9.]{1,6}) *([0-9]{6})([CP])([0-9]{8})$');
    if v_occ is not null then
      v_underlying  := coalesce(nullif(v_underlying, ''), v_occ[1]);
      v_expiration  := coalesce(v_expiration, to_date(v_occ[2], 'YYMMDD'));
      v_option_type := coalesce(v_option_type, case v_occ[3] when 'C' then 'call' else 'put' end);
      v_strike      := coalesce(v_strike, v_occ[4]::numeric / 1000);
    else
      v_underlying  := coalesce(nullif(v_underlying, ''), v_symbol);
    end if;
    if v_underlying is null or v_option_type is null or v_strike is null or v_expiration is null then
      raise exception 'Options need an underlying, type, strike and expiration (or an OCC symbol)'
        using errcode = '22023';
    end if;
    v_symbol := rpad(v_underlying, 6) || to_char(v_expiration, 'YYMMDD')
             || upper(left(v_option_type, 1)) || lpad(round(v_strike * 1000)::bigint::text, 8, '0');
  end if;

  select id into v_id from public.instruments where asset_class = p_asset_class and symbol = v_symbol;
  if found then
    return v_id;
  end if;

  if v_underlying is null or v_underlying = '' then
    v_underlying := case p_asset_class
      -- ESZ6 / ESZ26 -> ES
      when 'future' then regexp_replace(v_symbol, '[FGHJKMNQUVXZ][0-9]{1,2}$', '')
      -- BTC-USD / BTC/USD -> BTC
      when 'crypto' then split_part(replace(v_symbol, '/', '-'), '-', 1)
      else v_symbol
    end;
  end if;

  v_multiplier := coalesce(
    p_multiplier,
    case when p_asset_class = 'future'
      then (select fs.multiplier from public.futures_specs fs where fs.root_symbol = v_underlying)
    end,
    (select ac.default_multiplier from public.asset_classes ac where ac.id = p_asset_class),
    1
  );

  insert into public.instruments (
    asset_class, symbol, underlying_symbol, option_type, strike,
    expiration_date, multiplier, quote_currency, exchange
  ) values (
    p_asset_class, v_symbol, v_underlying, v_option_type, v_strike,
    v_expiration, v_multiplier, coalesce(p_quote_currency, 'USD'), p_exchange
  )
  on conflict (asset_class, symbol) do nothing
  returning id into v_id;

  if v_id is null then
    select id into v_id from public.instruments where asset_class = p_asset_class and symbol = v_symbol;
  end if;

  return v_id;
end;
$$;

revoke execute on function public.get_or_create_instrument(text, text, text, text, numeric, date, numeric, text, text) from public, anon;
grant  execute on function public.get_or_create_instrument(text, text, text, text, numeric, date, numeric, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Trades copy their market from the instrument.
-- -----------------------------------------------------------------------------
create or replace function public.trades_set_asset_class()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  select i.asset_class into new.asset_class from public.instruments i where i.id = new.instrument_id;
  return new;
end;
$$;

create trigger trades_set_asset_class
  before insert or update of instrument_id on public.trades
  for each row execute function public.trades_set_asset_class();

-- -----------------------------------------------------------------------------
-- Trade numbers are recalculated from executions on every change.
--
-- Entry price = average price of opening fills, exit price = average price of
-- closing fills. Realized P&L covers the closed quantity only, so a trade that
-- is still partly open shows what has been booked so far.
-- -----------------------------------------------------------------------------
create or replace function public.recalculate_trade(p_trade_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trade       public.trades%rowtype;
  v_multiplier  numeric;
  v_sign        integer;
  v_open_side   public.execution_side;
  v_open_qty    numeric;
  v_open_value  numeric;
  v_close_qty   numeric;
  v_close_value numeric;
  v_fees        numeric;
  v_count       integer;
  v_first_at    timestamptz;
  v_last_at     timestamptz;
  v_entry       numeric;
  v_exit        numeric;
  v_gross       numeric := 0;
  v_closed      boolean;
begin
  select * into v_trade from public.trades where id = p_trade_id for update;
  if not found then
    return;
  end if;

  select i.multiplier into v_multiplier from public.instruments i where i.id = v_trade.instrument_id;

  if v_trade.direction = 'long' then
    v_sign := 1;
    v_open_side := 'buy';
  else
    v_sign := -1;
    v_open_side := 'sell';
  end if;

  select
    coalesce(sum(e.quantity)             filter (where e.side =  v_open_side), 0),
    coalesce(sum(e.quantity * e.price)   filter (where e.side =  v_open_side), 0),
    coalesce(sum(e.quantity)             filter (where e.side <> v_open_side), 0),
    coalesce(sum(e.quantity * e.price)   filter (where e.side <> v_open_side), 0),
    coalesce(sum(e.commission + e.fees), 0),
    count(*),
    min(e.executed_at),
    max(e.executed_at)
  into v_open_qty, v_open_value, v_close_qty, v_close_value, v_fees, v_count, v_first_at, v_last_at
  from public.executions e
  where e.trade_id = p_trade_id;

  -- An imported trade whose fills were all removed (import undone) goes away.
  if v_count = 0 and v_trade.source = 'import' then
    delete from public.trades where id = p_trade_id;
    return;
  end if;

  v_entry := case when v_open_qty  > 0 then v_open_value  / v_open_qty  end;
  v_exit  := case when v_close_qty > 0 then v_close_value / v_close_qty end;

  if v_entry is not null and v_exit is not null then
    v_gross := least(v_open_qty, v_close_qty) * (v_exit - v_entry) * v_multiplier * v_sign;
  end if;

  v_closed := v_open_qty > 0 and v_close_qty >= v_open_qty;

  update public.trades set
    quantity        = v_open_qty,
    avg_entry_price = round(v_entry, 8),
    avg_exit_price  = round(v_exit, 8),
    gross_pnl       = round(v_gross, 4),
    fees            = round(v_fees, 4),
    net_pnl         = round(v_gross - v_fees, 4),
    execution_count = v_count,
    status          = case when v_closed then 'closed'::public.trade_status else 'open'::public.trade_status end,
    opened_at       = v_first_at,
    closed_at       = case when v_closed then v_last_at end
  where id = p_trade_id;
end;
$$;

revoke execute on function public.recalculate_trade(uuid) from public, anon, authenticated;

-- Statement-level so a 5,000 row import recalculates each trade once, not per fill.
create or replace function public.sync_trades_from_executions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trade_id uuid;
begin
  if tg_op = 'INSERT' then
    for v_trade_id in select distinct trade_id from new_rows loop
      perform public.recalculate_trade(v_trade_id);
    end loop;
  elsif tg_op = 'UPDATE' then
    for v_trade_id in select trade_id from new_rows union select trade_id from old_rows loop
      perform public.recalculate_trade(v_trade_id);
    end loop;
  else
    for v_trade_id in select distinct trade_id from old_rows loop
      perform public.recalculate_trade(v_trade_id);
    end loop;
  end if;
  return null;
end;
$$;

create trigger executions_sync_after_insert
  after insert on public.executions
  referencing new table as new_rows
  for each statement execute function public.sync_trades_from_executions();

create trigger executions_sync_after_update
  after update on public.executions
  referencing new table as new_rows old table as old_rows
  for each statement execute function public.sync_trades_from_executions();

create trigger executions_sync_after_delete
  after delete on public.executions
  referencing old table as old_rows
  for each statement execute function public.sync_trades_from_executions();

-- Changing a trade's direction or instrument changes its math too.
create or replace function public.trades_recalculate_on_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.recalculate_trade(new.id);
  return null;
end;
$$;

create trigger trades_recalculate_on_change
  after update of direction, instrument_id on public.trades
  for each row execute function public.trades_recalculate_on_change();
