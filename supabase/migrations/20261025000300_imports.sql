-- =============================================================================
-- Broker imports.
--
-- Every broker labels and orders its CSV columns differently. The app reads
-- the header row, matches it against import_templates.header_signature to
-- guess the broker, and maps each column to one of our fields. If the guess
-- is wrong the user fixes the mapping once and it is saved as their own
-- template for next time.
--
-- Raw rows are kept in import_rows, so a file can be re-processed after the
-- parser improves and a whole import can be undone by deleting it.
-- =============================================================================

create table public.import_templates (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid default auth.uid() references public.profiles (id) on delete cascade,
  broker_id        text not null references public.brokers (id),
  name             text not null,
  asset_class      text references public.asset_classes (id),
  header_signature text[] not null default '{}',
  column_mapping   jsonb not null default '{}'::jsonb,
  parse_options    jsonb not null default '{}'::jsonb,
  version          integer not null default 1,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

comment on table  public.import_templates is 'Column mappings per broker export. user_id null = built-in template shared with everyone.';
comment on column public.import_templates.header_signature is 'Normalized header names that identify this export format.';
comment on column public.import_templates.column_mapping is 'Our field -> their column, e.g. {"executed_at": "Exec Time", "price": "Price"}.';
comment on column public.import_templates.parse_options is 'Date format, delimiter, rows to skip, sign conventions, etc.';

create index import_templates_broker_idx on public.import_templates (broker_id);
create index import_templates_user_idx   on public.import_templates (user_id);

create table public.imports (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  broker_id         text references public.brokers (id),
  broker_account_id uuid,
  template_id       uuid references public.import_templates (id) on delete set null,
  file_name         text,
  file_size_bytes   bigint,
  storage_path      text,
  status            text not null default 'pending'
                      check (status in ('pending', 'mapping', 'processing', 'completed', 'failed')),
  column_mapping    jsonb not null default '{}'::jsonb,
  row_count         integer not null default 0,
  trade_count       integer not null default 0,
  execution_count   integer not null default 0,
  duplicate_count   integer not null default 0,
  error_count       integer not null default 0,
  errors            jsonb not null default '[]'::jsonb,
  started_at        timestamptz,
  completed_at      timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (id, user_id),
  foreign key (broker_account_id, user_id)
    references public.broker_accounts (id, user_id) on delete set null (broker_account_id)
);

create index imports_user_created_idx on public.imports (user_id, created_at desc);

create table public.import_rows (
  id           bigint generated always as identity primary key,
  import_id    uuid not null,
  user_id      uuid not null default auth.uid(),
  row_number   integer not null,
  raw          jsonb not null,
  status       text not null default 'pending'
                 check (status in ('pending', 'imported', 'duplicate', 'skipped', 'error')),
  error        text,
  execution_id uuid references public.executions (id) on delete set null,
  foreign key (import_id, user_id) references public.imports (id, user_id) on delete cascade,
  unique (import_id, row_number)
);

-- Undoing an import deletes it. Its executions go with it, and a trade left
-- with no executions is removed by the trade recalculation trigger.
alter table public.executions
  add foreign key (import_id, user_id) references public.imports (id, user_id) on delete cascade;
alter table public.trades
  add foreign key (import_id, user_id) references public.imports (id, user_id) on delete set null (import_id);

create index executions_import_idx on public.executions (import_id);
create index trades_import_idx     on public.trades (import_id);

create trigger import_templates_set_updated_at before update on public.import_templates for each row execute function public.set_updated_at();
create trigger imports_set_updated_at          before update on public.imports          for each row execute function public.set_updated_at();
