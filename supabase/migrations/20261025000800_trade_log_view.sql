-- =============================================================================
-- Trade log view: one flat row per trade for the trade log page.
--
-- Joins in the symbol, setup name, tag names and list ids so the page can
-- filter, sort, search and paginate with plain supabase-js calls on a single
-- "table". security_invoker makes it run as the caller, so the row level
-- security on trades (and the other tables) still applies.
-- =============================================================================

create view public.trade_log
with (security_invoker = true)
as
select
  t.id,
  t.user_id,
  t.asset_class,
  t.direction,
  t.status,
  t.opened_at,
  t.closed_at,
  coalesce(t.closed_at, t.opened_at)    as trade_date,
  t.quantity,
  t.avg_entry_price,
  t.avg_exit_price,
  t.gross_pnl,
  t.fees,
  t.net_pnl,
  t.r_multiple,
  t.hold_seconds,
  t.planned_risk,
  t.rating,
  t.broker_account_id,
  t.setup_id,
  t.source,
  t.import_id,
  t.created_at,
  i.symbol,
  i.underlying_symbol,
  i.option_type,
  i.strike,
  i.expiration_date,
  i.multiplier,
  s.name                                as setup_name,
  coalesce(tg.tag_names, '{}')          as tag_names,
  coalesce(li.trade_list_ids, '{}')     as trade_list_ids,
  lower(concat_ws(' ', i.symbol, i.underlying_symbol, s.name,
                  array_to_string(tg.tag_names, ' '))) as search_text
from public.trades t
join public.instruments i on i.id = t.instrument_id
left join public.setups s on s.id = t.setup_id
left join lateral (
  select array_agg(g.name order by g.name) as tag_names
  from public.trade_tags tt
  join public.tags g on g.id = tt.tag_id
  where tt.trade_id = t.id
) tg on true
left join lateral (
  select array_agg(l.trade_list_id) as trade_list_ids
  from public.trade_list_items l
  where l.trade_id = t.id
) li on true;

comment on view public.trade_log is
  'Read-only, one row per trade with symbol, setup, tags and lists flattened in. Write to trades/executions, not here.';
comment on column public.trade_log.trade_date is
  'Close time for closed trades, open time for open ones. What the trade log shows, sorts and date-filters on.';
comment on column public.trade_log.search_text is
  'Lower-cased symbol, underlying, setup and tag names for the search box (ilike).';

revoke all on public.trade_log from anon;
revoke insert, update, delete, truncate on public.trade_log from authenticated;
grant select on public.trade_log to authenticated;
