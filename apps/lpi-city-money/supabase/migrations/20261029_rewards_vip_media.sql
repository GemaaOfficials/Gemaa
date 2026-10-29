alter table public.lpi_users
  add column if not exists vip_expires_at timestamptz,
  add column if not exists vip_lifetime boolean not null default false,
  add column if not exists next_payment_cashback_percent integer not null default 0;

update public.lpi_users
set vip_lifetime = true
where is_vip = true and vip_expires_at is null and vip_lifetime = false;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='lpi_users_next_payment_cashback_percent_check') then
    alter table public.lpi_users add constraint lpi_users_next_payment_cashback_percent_check
      check (next_payment_cashback_percent between 0 and 50);
  end if;
end $$;

create table if not exists public.lpi_spin_config (
  id integer primary key default 1 check (id = 1),
  reward_config jsonb not null default
    '[{"type":"coins","amount":10,"label":"10 LPI bonus coins","weight":3},
      {"type":"coins","amount":20,"label":"20 LPI bonus coins","weight":3},
      {"type":"coins","amount":30,"label":"30 LPI bonus coins","weight":2},
      {"type":"cashback","amount":20,"label":"20% cashback coupon","weight":1},
      {"type":"vip","amount":10,"label":"10-minute VIP pass","weight":1}]'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.lpi_users(id)
);
insert into public.lpi_spin_config(id) values (1) on conflict (id) do nothing;

create table if not exists public.lpi_spin_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.lpi_users(id) on delete cascade,
  spin_date date not null,
  reward_type text not null,
  reward_amount integer not null default 0,
  reward_label text not null,
  created_at timestamptz not null default now(),
  unique(user_id, spin_date)
);
create index if not exists lpi_spin_history_created_idx on public.lpi_spin_history(created_at desc);

create table if not exists public.lpi_media_cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.lpi_users(id) on delete cascade,
  admin_user_id uuid not null references public.lpi_users(id),
  title text not null,
  media_url text not null,
  content_type text not null check (content_type in ('image/jpeg','image/png','image/webp','video/mp4')),
  created_at timestamptz not null default now()
);
create index if not exists lpi_media_cards_user_created_idx on public.lpi_media_cards(user_id, created_at desc);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('lpi-admin-media', 'lpi-admin-media', true, 4194304, array['image/jpeg','image/png','image/webp','video/mp4'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.lpi_transfer(p_from uuid, p_to uuid, p_amount bigint, p_method text default 'direct')
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_payer public.lpi_users%rowtype;
  v_payee public.lpi_users%rowtype;
  v_discount bigint := 0;
  v_debit bigint;
  v_cashback bigint := 0;
  v_pct integer := 0;
  v_transfer_id uuid;
  v_vip_active boolean := false;
begin
  if p_amount is null or p_amount <= 0 or p_amount > 100000000 then
    raise exception 'Enter a valid game-coin amount.';
  end if;
  if p_from = p_to then raise exception 'You cannot pay your own account.'; end if;
  select * into v_payer from public.lpi_users where id = p_from for update;
  if not found then raise exception 'Payer account not found.'; end if;
  select * into v_payee from public.lpi_users where id = p_to for update;
  if not found then raise exception 'Receiver account not found.'; end if;

  v_vip_active := v_payer.is_vip and (v_payer.vip_lifetime or v_payer.vip_expires_at is null or v_payer.vip_expires_at > now());
  if v_vip_active then
    v_discount := floor(p_amount * 0.03)::bigint;
    v_pct := 1 + floor(random() * 20)::integer;
  end if;
  v_pct := greatest(v_pct, coalesce(v_payer.next_payment_cashback_percent, 0));
  if v_pct > 0 then v_cashback := floor(p_amount * v_pct / 100.0)::bigint; end if;
  v_debit := p_amount - v_discount;
  if v_payer.balance < v_debit then raise exception 'Not enough LPI game coins.'; end if;

  update public.lpi_users
    set balance = balance - v_debit + v_cashback,
        next_payment_cashback_percent = case when coalesce(v_payer.next_payment_cashback_percent,0) > 0 then 0 else next_payment_cashback_percent end
    where id = p_from;
  update public.lpi_users set balance = balance + p_amount where id = p_to;

  insert into public.lpi_transfers(from_user_id,to_user_id,amount,payer_debit,discount,cashback,cashback_percent,payment_method)
  values (p_from,p_to,p_amount,v_debit,v_discount,v_cashback,v_pct,coalesce(nullif(p_method,''),'direct'))
  returning id into v_transfer_id;
  return jsonb_build_object('transfer_id',v_transfer_id,'amount',p_amount,'debit',v_debit,'discount',v_discount,'cashback',v_cashback,'cashback_percent',v_pct);
end;
$$;

drop function if exists public.lpi_buy_vip(uuid);
create or replace function public.lpi_buy_vip(p_user_id uuid, p_duration text default '30m')
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user public.lpi_users%rowtype;
  v_cost bigint;
  v_lifetime boolean;
  v_expiry timestamptz;
begin
  if p_duration not in ('30m','lifetime') then raise exception 'Choose 30-minute or lifetime VIP.'; end if;
  v_cost := case when p_duration = 'lifetime' then 19999 else 1999 end;
  v_lifetime := p_duration = 'lifetime';
  select * into v_user from public.lpi_users where id=p_user_id for update;
  if not found then raise exception 'Account not found.'; end if;
  if v_user.is_vip and (
      v_user.vip_lifetime
      or (v_user.vip_expires_at is null and p_duration <> 'lifetime')
      or (v_user.vip_expires_at > now() and p_duration = '30m')
    ) then
    raise exception 'This account already has active VIP, or the requested plan does not upgrade it.';
  end if;
  if v_user.balance < v_cost then
    raise exception 'Not enough LPI game coins for this VIP pass.';
  end if;
  if not v_lifetime then v_expiry := now() + interval '30 minutes'; end if;
  update public.lpi_users
    set balance = balance - v_cost, is_vip = true, vip_lifetime = v_lifetime, vip_expires_at = v_expiry
    where id = p_user_id;
  insert into public.lpi_transfers(from_user_id,amount,payer_debit,payment_method,note)
  values (p_user_id,v_cost,v_cost,'vip-purchase',case when v_lifetime then 'Lifetime VIP (game coins)' else '30-minute VIP pass (game coins)' end);
  insert into public.lpi_announcements(message,kind)
  values (v_user.display_name || ' unlocked ' || case when v_lifetime then 'Lifetime VIP' else '30-minute VIP' end, 'vip');
  return jsonb_build_object('success',true,'cost',v_cost,'duration',p_duration,'lifetime',v_lifetime,'expiresAt',v_expiry);
end;
$$;

create or replace function public.lpi_play_spin(p_user_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user public.lpi_users%rowtype;
  v_rewards jsonb;
  v_item jsonb;
  v_reward jsonb;
  v_total numeric := 0;
  v_cursor numeric := 0;
  v_pick numeric;
  v_weight numeric;
  v_today date := (now() at time zone 'utc')::date;
  v_type text;
  v_amount integer;
  v_label text;
  v_expires timestamptz;
  v_balance bigint;
begin
  select * into v_user from public.lpi_users where id=p_user_id for update;
  if not found then raise exception 'Account not found.'; end if;

  if exists(select 1 from public.lpi_spin_history where user_id=p_user_id and spin_date=v_today) then
    raise exception 'You have already used today’s spin. Come back tomorrow.';
  end if;

  select reward_config into v_rewards from public.lpi_spin_config where id=1;
  if v_rewards is null or jsonb_typeof(v_rewards) <> 'array' or jsonb_array_length(v_rewards)=0 then
    raise exception 'The city spin is temporarily unavailable.';
  end if;

  for v_item in select value from jsonb_array_elements(v_rewards) loop
    v_weight := greatest(0, coalesce((v_item->>'weight')::numeric, 1));
    v_total := v_total + v_weight;
  end loop;
  if v_total <= 0 then raise exception 'The city spin has no active rewards.'; end if;
  v_pick := random() * v_total;
  for v_item in select value from jsonb_array_elements(v_rewards) loop
    v_cursor := v_cursor + greatest(0, coalesce((v_item->>'weight')::numeric, 1));
    if v_pick <= v_cursor then v_reward := v_item; exit; end if;
  end loop;
  if v_reward is null then v_reward := v_rewards->(jsonb_array_length(v_rewards)-1); end if;

  v_type := coalesce(v_reward->>'type','');
  v_amount := greatest(1,coalesce((v_reward->>'amount')::integer,1));
  v_label := left(coalesce(v_reward->>'label','City spin prize'),100);
  if v_type not in ('coins','cashback','vip') then raise exception 'The city spin reward is invalid.'; end if;
  if v_type='cashback' and v_amount > 50 then raise exception 'Cashback reward exceeds the permitted limit.'; end if;
  if v_type='vip' and v_amount > 1440 then raise exception 'VIP duration exceeds the permitted limit.'; end if;
  if v_type='coins' and v_amount > 100000 then raise exception 'Game-coin reward exceeds the permitted limit.'; end if;

  insert into public.lpi_spin_history(user_id,spin_date,reward_type,reward_amount,reward_label)
  values (p_user_id,v_today,v_type,v_amount,v_label);

  if v_type='coins' then
    update public.lpi_users set balance=balance+v_amount where id=p_user_id returning balance into v_balance;
    insert into public.lpi_transfers(to_user_id,amount,payment_method,note)
    values(p_user_id,v_amount,'spin-reward',left('Global Spin: '||v_label,120));
  elsif v_type='cashback' then
    update public.lpi_users
      set next_payment_cashback_percent=greatest(next_payment_cashback_percent,v_amount)
      where id=p_user_id;
  elsif v_type='vip' then
    if v_user.vip_lifetime then
      v_type := 'coins';
      v_amount := 30;
      v_label := '30 LPI bonus coins (VIP already lifetime)';
      update public.lpi_users set balance=balance+v_amount where id=p_user_id returning balance into v_balance;
      insert into public.lpi_transfers(to_user_id,amount,payment_method,note)
      values(p_user_id,v_amount,'spin-reward',left('Global Spin: '||v_label,120));
    else
      if v_user.is_vip and v_user.vip_expires_at > now() then
        v_expires := v_user.vip_expires_at + make_interval(mins => v_amount);
      else
        v_expires := now() + make_interval(mins => v_amount);
      end if;
      update public.lpi_users set is_vip=true,vip_lifetime=false,vip_expires_at=v_expires where id=p_user_id;
    end if;
  end if;

  update public.lpi_spin_history
    set reward_type=v_type,reward_amount=v_amount,reward_label=v_label
    where user_id=p_user_id and spin_date=v_today;
  if v_type='vip' then
    insert into public.lpi_announcements(message,kind)
    values(v_user.display_name || ' won a VIP pass from Global Spin','vip');
  end if;

  return jsonb_build_object('type',v_type,'amount',v_amount,'label',v_label,'spinDate',v_today,'balance',v_balance);
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array['lpi_spin_config','lpi_spin_history','lpi_media_cards'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from anon, authenticated',t);
    execute format('grant all on table public.%I to service_role',t);
  end loop;
end $$;

revoke all on function public.lpi_buy_vip(uuid,text) from public, anon, authenticated;
revoke all on function public.lpi_play_spin(uuid) from public, anon, authenticated;
grant execute on function public.lpi_buy_vip(uuid,text) to service_role;
grant execute on function public.lpi_play_spin(uuid) to service_role;
