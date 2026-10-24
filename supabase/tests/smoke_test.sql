-- Smoke test for the schema. Runs in a transaction and rolls everything back.
-- Run with scripts/db/test-migrations.sh, or against a local Supabase with:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/smoke_test.sql

begin;

-- Two users. Signing up must create their profiles.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'alice@example.com', '{"full_name": "Alice"}'),
  ('00000000-0000-0000-0000-00000000000b', 'bob@example.com',   '{}');

do $$
begin
  assert (select display_name from public.profiles where id = '00000000-0000-0000-0000-00000000000a') = 'Alice', 'profile from metadata';
  assert (select display_name from public.profiles where id = '00000000-0000-0000-0000-00000000000b') = 'bob',   'profile from email';
  assert (select plan_id from public.profiles where id = '00000000-0000-0000-0000-00000000000a') = 'free',       'default plan';
end $$;

-- ---------------------------------------------------------------------------
-- Everything below runs as Alice, through the same role the app uses.
-- ---------------------------------------------------------------------------
set local role authenticated;
do $$ begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', true); end $$;

do $$
declare
  v_account uuid;
  v_stock   uuid;
  v_option  uuid;
  v_future  uuid;
  v_trade   uuid;
  v_t       public.trades%rowtype;
  v_list1   uuid;
  v_list2   uuid;
  v_import  uuid;
  v_stats   record;
begin
  insert into public.broker_accounts (broker_id, name) values ('schwab', 'Schwab options') returning id into v_account;

  -- Instruments
  v_stock  := public.get_or_create_instrument('stock', ' aapl ');
  assert v_stock = public.get_or_create_instrument('stock', 'AAPL'), 'instrument is reused';

  v_option := public.get_or_create_instrument('option', 'AAPL261218C00150000');
  assert v_option = public.get_or_create_instrument('option', 'AAPL', null, 'call', 150, date '2026-12-18'),
    'option fields and OCC symbol resolve to the same instrument';
  assert (select multiplier from public.instruments where id = v_option) = 100, 'option multiplier';
  assert (select symbol from public.instruments where id = v_option) = 'AAPL  261218C00150000', 'canonical OCC symbol';

  v_future := public.get_or_create_instrument('future', 'ESZ6');
  assert (select underlying_symbol from public.instruments where id = v_future) = 'ES', 'futures root';
  assert (select multiplier from public.instruments where id = v_future) = 50, 'futures multiplier from specs';

  -- Stock: scale in twice, exit once. Avg entry 11, exit 13, fees 3.
  insert into public.trades (instrument_id, direction, broker_account_id) values (v_stock, 'long', v_account) returning id into v_trade;
  insert into public.executions (trade_id, side, quantity, price, commission, executed_at) values
    (v_trade, 'buy',  100, 10, 1, '2026-11-02 14:31:00+00'),
    (v_trade, 'buy',  100, 12, 1, '2026-11-02 14:45:00+00'),
    (v_trade, 'sell', 200, 13, 1, '2026-11-02 15:10:00+00');
  select * into v_t from public.trades where id = v_trade;
  assert v_t.asset_class = 'stock', 'asset class copied';
  assert v_t.status = 'closed', 'stock trade closed';
  assert v_t.avg_entry_price = 11 and v_t.avg_exit_price = 13, 'stock averages';
  assert v_t.gross_pnl = 400 and v_t.fees = 3 and v_t.net_pnl = 397, 'stock P&L';
  assert v_t.hold_seconds = 2340, 'hold time';

  -- Option: 2 contracts, 1.50 -> 2.00 = $100.
  insert into public.trades (instrument_id, direction) values (v_option, 'long') returning id into v_trade;
  insert into public.executions (trade_id, side, quantity, price, executed_at) values
    (v_trade, 'buy',  2, 1.50, '2026-11-03 15:00:00+00'),
    (v_trade, 'sell', 2, 2.00, '2026-11-03 16:00:00+00');
  assert (select net_pnl from public.trades where id = v_trade) = 100, 'option P&L uses multiplier';

  -- Future short: 5000 -> 4990 on ES = $500.
  insert into public.trades (instrument_id, direction, planned_risk) values (v_future, 'short', 250) returning id into v_trade;
  insert into public.executions (trade_id, side, quantity, price, executed_at) values
    (v_trade, 'sell', 1, 5000, '2026-11-04 14:00:00+00'),
    (v_trade, 'buy',  1, 4990, '2026-11-04 14:20:00+00');
  select * into v_t from public.trades where id = v_trade;
  assert v_t.net_pnl = 500, 'short futures P&L';
  assert v_t.r_multiple = 2, 'R multiple';

  -- Partly closed trade stays open with realized P&L so far.
  insert into public.trades (instrument_id, direction) values (v_stock, 'long') returning id into v_trade;
  insert into public.executions (trade_id, side, quantity, price, executed_at) values
    (v_trade, 'buy',  10, 5, '2026-11-05 14:00:00+00'),
    (v_trade, 'sell',  4, 6, '2026-11-05 15:00:00+00');
  select * into v_t from public.trades where id = v_trade;
  assert v_t.status = 'open' and v_t.closed_at is null and v_t.gross_pnl = 4, 'partial close';

  -- Editing a fill recalculates the trade.
  update public.executions set quantity = 10 where trade_id = v_trade and side = 'sell';
  assert (select status from public.trades where id = v_trade) = 'closed', 'recalc on update';
  delete from public.trades where id = v_trade;

  -- Calculated columns cannot be written by the client.
  begin
    update public.trades set net_pnl = 1000000;
    raise exception 'expected permission error';
  exception when insufficient_privilege then null;
  end;

  -- Plan columns cannot be written by the client.
  begin
    update public.profiles set plan_id = 'pro';
    raise exception 'expected permission error';
  exception when insufficient_privilege then null;
  end;

  -- Trade lists: two allowed on the free plan, the third is refused.
  insert into public.trade_lists (name) values ('Schwab options') returning id into v_list1;
  insert into public.trade_lists (name) values ('Fidelity stocks') returning id into v_list2;
  begin
    insert into public.trade_lists (name) values ('One too many');
    raise exception 'expected list limit error';
  exception when raise_exception then
    assert sqlerrm like 'Your plan allows up to 2 trade lists.%', sqlerrm;
  end;

  insert into public.trade_list_items (trade_list_id, trade_id)
    select v_list1, id from public.trades where asset_class = 'option';

  -- Analytics
  select * into v_stats from public.get_trade_stats();
  assert v_stats.trade_count = 3, 'three closed trades';
  assert v_stats.net_pnl = 997, 'total net P&L';
  assert v_stats.win_rate = 1, 'win rate';

  select * into v_stats from public.get_trade_stats(p_trade_list_id => v_list1);
  assert v_stats.trade_count = 1 and v_stats.net_pnl = 100, 'list filter';

  select * into v_stats from public.get_trade_stats(p_asset_class => 'future');
  assert v_stats.net_pnl = 500, 'market tab filter';

  assert (select count(*) from public.get_daily_pnl()) = 3, 'one row per day';
  assert (select max(cumulative_net_pnl) from public.get_daily_pnl()) = 997, 'equity curve';
  assert (select count(*) from public.get_performance_breakdown('asset_class')) = 3, 'breakdown by market';
  assert (select net_pnl from public.get_performance_breakdown('trade_list') where group_key = 'Not in a list') = 897, 'breakdown by list';
  perform public.get_performance_breakdown(g)
    from unnest(array['symbol','instrument','setup','tag','broker_account','direction','day_of_week','hour_of_day']) g;

  -- Imports: re-importing a fill is blocked, and undoing an import removes its trades.
  insert into public.imports (broker_id, file_name) values ('tradovate', 'fills.csv') returning id into v_import;
  insert into public.trades (instrument_id, direction, source, import_id) values (v_future, 'long', 'import', v_import) returning id into v_trade;
  insert into public.executions (trade_id, side, quantity, price, executed_at, import_id, dedupe_key) values
    (v_trade, 'buy',  1, 5000, '2026-11-06 14:00:00+00', v_import, 'tradovate:1'),
    (v_trade, 'sell', 1, 5004, '2026-11-06 14:05:00+00', v_import, 'tradovate:2');
  assert (select net_pnl from public.trades where id = v_trade) = 200, 'imported trade';
  begin
    insert into public.executions (trade_id, side, quantity, price, executed_at, dedupe_key)
      values (v_trade, 'buy', 1, 5000, '2026-11-06 14:00:00+00', 'tradovate:1');
    raise exception 'expected duplicate error';
  exception when unique_violation then null;
  end;
  delete from public.imports where id = v_import;
  assert not exists (select 1 from public.trades where id = v_trade), 'undo import';
end $$;

-- ---------------------------------------------------------------------------
-- Bob sees none of Alice's data and cannot attach to it.
-- ---------------------------------------------------------------------------
do $$ begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', true); end $$;

do $$
declare
  v_list uuid;
begin
  assert (select count(*) from public.trades) = 0, 'trades are private';
  assert (select count(*) from public.trade_lists) = 0, 'lists are private';
  assert (select count(*) from public.profiles) = 1, 'profiles are private';
  assert (select trade_count from public.get_trade_stats()) = 0, 'stats are private';

  update public.trades set notes = 'hacked';
  insert into public.trade_lists (name) values ('Mine') returning id into v_list;

  begin
    insert into public.trade_list_items (trade_list_id, trade_id)
      select v_list, t.id from public.trades t;  -- sees nothing, so nothing to insert
    insert into public.trade_list_items (trade_list_id, trade_id, user_id)
      values (v_list, gen_random_uuid(), '00000000-0000-0000-0000-00000000000a');
    raise exception 'expected RLS error';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;

do $$
begin
  assert not exists (select 1 from public.trades where notes = 'hacked'), 'cross-user update blocked';
end $$;

rollback;

\echo 'Smoke test passed'
