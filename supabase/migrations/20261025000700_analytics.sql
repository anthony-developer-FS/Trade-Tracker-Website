-- =============================================================================
-- Analytics functions, called from the app with supabase.rpc(...).
--
-- They all take the same optional filters, so every dashboard widget can be
-- scoped to a date range, a market tab, a trade list or a broker account.
-- They run as the calling user, so row level security still applies.
-- Only closed trades count toward performance numbers.
-- =============================================================================

create or replace function public.filtered_trades(
  p_from              timestamptz default null,
  p_to                timestamptz default null,
  p_asset_class       text        default null,
  p_trade_list_id     uuid        default null,
  p_broker_account_id uuid        default null
)
returns setof public.trades
language sql
stable
set search_path = ''
as $$
  select t.*
  from public.trades t
  where t.user_id = (select auth.uid())
    and t.status = 'closed'
    and (p_from is null or t.closed_at >= p_from)
    and (p_to   is null or t.closed_at <  p_to)
    and (p_asset_class       is null or t.asset_class = p_asset_class)
    and (p_broker_account_id is null or t.broker_account_id = p_broker_account_id)
    and (p_trade_list_id     is null or exists (
          select 1 from public.trade_list_items li
          where li.trade_id = t.id and li.trade_list_id = p_trade_list_id));
$$;

-- -----------------------------------------------------------------------------
-- Headline stats: win rate, average win/loss, profit factor, expectancy, ...
-- -----------------------------------------------------------------------------
create or replace function public.get_trade_stats(
  p_from              timestamptz default null,
  p_to                timestamptz default null,
  p_asset_class       text        default null,
  p_trade_list_id     uuid        default null,
  p_broker_account_id uuid        default null
)
returns table (
  trade_count      bigint,
  winners          bigint,
  losers           bigint,
  breakeven        bigint,
  win_rate         numeric,
  gross_pnl        numeric,
  fees             numeric,
  net_pnl          numeric,
  avg_win          numeric,
  avg_loss         numeric,
  largest_win      numeric,
  largest_loss     numeric,
  profit_factor    numeric,
  expectancy       numeric,
  avg_r_multiple   numeric,
  avg_hold_seconds numeric
)
language sql
stable
set search_path = ''
as $$
  select
    count(*),
    count(*) filter (where t.net_pnl > 0),
    count(*) filter (where t.net_pnl < 0),
    count(*) filter (where t.net_pnl = 0),
    round(count(*) filter (where t.net_pnl > 0)::numeric / nullif(count(*), 0), 4),
    coalesce(sum(t.gross_pnl), 0),
    coalesce(sum(t.fees), 0),
    coalesce(sum(t.net_pnl), 0),
    round(avg(t.net_pnl) filter (where t.net_pnl > 0), 2),
    round(avg(t.net_pnl) filter (where t.net_pnl < 0), 2),
    max(t.net_pnl) filter (where t.net_pnl > 0),
    min(t.net_pnl) filter (where t.net_pnl < 0),
    round(sum(t.net_pnl) filter (where t.net_pnl > 0)
          / nullif(abs(sum(t.net_pnl) filter (where t.net_pnl < 0)), 0), 2),
    round(avg(t.net_pnl), 2),
    round(avg(t.r_multiple), 2),
    round(avg(t.hold_seconds))
  from public.filtered_trades(p_from, p_to, p_asset_class, p_trade_list_id, p_broker_account_id) t;
$$;

-- -----------------------------------------------------------------------------
-- Daily P&L in the user's time zone, with a running total for the equity
-- curve. Also feeds the calendar heatmap.
-- -----------------------------------------------------------------------------
create or replace function public.get_daily_pnl(
  p_from              timestamptz default null,
  p_to                timestamptz default null,
  p_asset_class       text        default null,
  p_trade_list_id     uuid        default null,
  p_broker_account_id uuid        default null
)
returns table (
  trade_date         date,
  trade_count        bigint,
  winners            bigint,
  losers             bigint,
  net_pnl            numeric,
  cumulative_net_pnl numeric
)
language sql
stable
set search_path = ''
as $$
  with tz as (
    select coalesce(
      (select p.timezone from public.profiles p where p.id = (select auth.uid())),
      'UTC') as name
  ),
  daily as (
    select
      (t.closed_at at time zone tz.name)::date as day,
      count(*)                                 as n,
      count(*) filter (where t.net_pnl > 0)    as w,
      count(*) filter (where t.net_pnl < 0)    as l,
      sum(t.net_pnl)                           as pnl
    from public.filtered_trades(p_from, p_to, p_asset_class, p_trade_list_id, p_broker_account_id) t
    cross join tz
    group by 1
  )
  select d.day, d.n, d.w, d.l, d.pnl, sum(d.pnl) over (order by d.day)
  from daily d
  order by d.day;
$$;

-- -----------------------------------------------------------------------------
-- Performance broken down by one dimension. Supported p_group_by values:
--   symbol, instrument, setup, tag, trade_list, broker_account, asset_class,
--   direction, day_of_week, hour_of_day
-- A trade with two tags counts once under each tag.
-- -----------------------------------------------------------------------------
create or replace function public.get_performance_breakdown(
  p_group_by          text,
  p_from              timestamptz default null,
  p_to                timestamptz default null,
  p_asset_class       text        default null,
  p_trade_list_id     uuid        default null,
  p_broker_account_id uuid        default null
)
returns table (
  group_key     text,
  sort_key      numeric,
  trade_count   bigint,
  winners       bigint,
  win_rate      numeric,
  net_pnl       numeric,
  avg_net_pnl   numeric,
  profit_factor numeric
)
language plpgsql
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tz text;
begin
  if p_group_by not in ('symbol', 'instrument', 'setup', 'tag', 'trade_list', 'broker_account',
                        'asset_class', 'direction', 'day_of_week', 'hour_of_day') then
    raise exception 'Unsupported group_by value: %', p_group_by using errcode = '22023';
  end if;

  select p.timezone into v_tz from public.profiles p where p.id = auth.uid();
  v_tz := coalesce(v_tz, 'UTC');

  return query
  select
    k.key,
    min(k.sort),
    count(*),
    count(*) filter (where t.net_pnl > 0),
    round(count(*) filter (where t.net_pnl > 0)::numeric / count(*), 4),
    sum(t.net_pnl),
    round(avg(t.net_pnl), 2),
    round(sum(t.net_pnl) filter (where t.net_pnl > 0)
          / nullif(abs(sum(t.net_pnl) filter (where t.net_pnl < 0)), 0), 2)
  from public.filtered_trades(p_from, p_to, p_asset_class, p_trade_list_id, p_broker_account_id) t
  join public.instruments i on i.id = t.instrument_id
  cross join lateral (
    select i.underlying_symbol as key, null::numeric as sort where p_group_by = 'symbol'
    union all
    select i.symbol, null where p_group_by = 'instrument'
    union all
    select coalesce((select s.name from public.setups s where s.id = t.setup_id), 'No setup'), null
      where p_group_by = 'setup'
    union all
    select coalesce((select ba.name from public.broker_accounts ba where ba.id = t.broker_account_id), 'No account'), null
      where p_group_by = 'broker_account'
    union all
    select ac.name, ac.sort_order::numeric from public.asset_classes ac
      where p_group_by = 'asset_class' and ac.id = t.asset_class
    union all
    select t.direction::text, null where p_group_by = 'direction'
    union all
    select trim(to_char(t.closed_at at time zone v_tz, 'Day')),
           extract(isodow from t.closed_at at time zone v_tz)
      where p_group_by = 'day_of_week'
    union all
    select to_char(t.opened_at at time zone v_tz, 'HH24:00'),
           extract(hour from t.opened_at at time zone v_tz)
      where p_group_by = 'hour_of_day'
    union all
    select tg.name, null from public.trade_tags tt join public.tags tg on tg.id = tt.tag_id
      where p_group_by = 'tag' and tt.trade_id = t.id
    union all
    select 'No tags', null
      where p_group_by = 'tag' and not exists (select 1 from public.trade_tags tt where tt.trade_id = t.id)
    union all
    select tl.name, tl.sort_order::numeric from public.trade_list_items li join public.trade_lists tl on tl.id = li.trade_list_id
      where p_group_by = 'trade_list' and li.trade_id = t.id
    union all
    select 'Not in a list', null
      where p_group_by = 'trade_list' and not exists (select 1 from public.trade_list_items li where li.trade_id = t.id)
  ) k
  group by k.key
  order by min(k.sort) nulls last, sum(t.net_pnl) desc;
end;
$$;

revoke execute on function public.filtered_trades(timestamptz, timestamptz, text, uuid, uuid) from public, anon;
revoke execute on function public.get_trade_stats(timestamptz, timestamptz, text, uuid, uuid) from public, anon;
revoke execute on function public.get_daily_pnl(timestamptz, timestamptz, text, uuid, uuid) from public, anon;
revoke execute on function public.get_performance_breakdown(text, timestamptz, timestamptz, text, uuid, uuid) from public, anon;
grant  execute on function public.filtered_trades(timestamptz, timestamptz, text, uuid, uuid) to authenticated;
grant  execute on function public.get_trade_stats(timestamptz, timestamptz, text, uuid, uuid) to authenticated;
grant  execute on function public.get_daily_pnl(timestamptz, timestamptz, text, uuid, uuid) to authenticated;
grant  execute on function public.get_performance_breakdown(text, timestamptz, timestamptz, text, uuid, uuid) to authenticated;
