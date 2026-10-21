-- Remim Browser: Supabase schema
-- Run in the Supabase SQL Editor using a project owner account.
-- Clients must use only the publishable/anon key. Never ship service_role keys.

create extension if not exists pgcrypto;

create table if not exists public.bookmarks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  url text not null check (char_length(url) between 8 and 4096),
  title text not null default '' check (char_length(title) <= 300),
  created_at timestamptz not null default now(),
  unique (user_id, url)
);

create index if not exists bookmarks_user_created_idx
  on public.bookmarks (user_id, created_at desc);

create table if not exists public.browsing_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  url text not null check (char_length(url) between 8 and 4096),
  title text not null default '' check (char_length(title) <= 300),
  visited_at timestamptz not null default now()
);

create index if not exists browsing_history_user_visited_idx
  on public.browsing_history (user_id, visited_at desc);
create index if not exists browsing_history_user_url_idx
  on public.browsing_history (user_id, url);

create table if not exists public.device_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null check (char_length(device_id) between 8 and 160),
  device_name text not null default 'Remim device' check (char_length(device_name) <= 160),
  platform text not null default 'unknown' check (char_length(platform) <= 80),
  current_url text check (current_url is null or char_length(current_url) <= 4096),
  current_title text not null default '' check (char_length(current_title) <= 300),
  last_seen timestamptz not null default now(),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (user_id, device_id)
);

create index if not exists device_sessions_user_seen_idx
  on public.device_sessions (user_id, last_seen desc);

create table if not exists public.session_transfers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  sender_device_id text not null check (char_length(sender_device_id) between 8 and 160),
  target_device_id text check (target_device_id is null or char_length(target_device_id) between 8 and 160),
  url text not null check (url ~ '^https?://' and char_length(url) <= 4096),
  title text not null default '' check (char_length(title) <= 300),
  status text not null default 'pending' check (status in ('pending', 'claimed', 'expired', 'dismissed')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '10 minutes'),
  claimed_at timestamptz,
  check (expires_at > created_at)
);

create index if not exists session_transfers_user_created_idx
  on public.session_transfers (user_id, created_at desc);
create index if not exists session_transfers_pending_expiry_idx
  on public.session_transfers (user_id, expires_at)
  where status = 'pending';

-- Row-level security: each signed-in user sees only their own data.
alter table public.bookmarks enable row level security;
alter table public.browsing_history enable row level security;
alter table public.device_sessions enable row level security;
alter table public.session_transfers enable row level security;

drop policy if exists "Users manage their own bookmarks" on public.bookmarks;
create policy "Users manage their own bookmarks"
  on public.bookmarks for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users manage their own browsing history" on public.browsing_history;
create policy "Users manage their own browsing history"
  on public.browsing_history for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users manage their own device sessions" on public.device_sessions;
create policy "Users manage their own device sessions"
  on public.device_sessions for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users manage their own session transfers" on public.session_transfers;
create policy "Users manage their own session transfers"
  on public.session_transfers for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.bookmarks to authenticated;
grant select, insert, update, delete on public.browsing_history to authenticated;
grant select, insert, update, delete on public.device_sessions to authenticated;
grant select, insert, update, delete on public.session_transfers to authenticated;

-- Realtime is needed for cross-device transfer notifications.
-- Safe to run repeatedly, even when the table is already in the publication.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'session_transfers'
     ) then
    execute 'alter publication supabase_realtime add table public.session_transfers';
  end if;
end $$;

alter table public.session_transfers replica identity full;

-- Optional cleanup job (run from a trusted scheduler; client cannot clean other users' data).
-- delete from public.session_transfers where expires_at < now() - interval '7 days';
