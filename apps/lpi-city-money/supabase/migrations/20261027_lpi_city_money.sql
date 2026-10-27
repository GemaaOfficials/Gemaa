-- LPI City Money: fictional game currency only. No real UPI/bank rails.
-- All client access is through the lpi-api Edge Function; these tables have no client policies.

create table if not exists public.lpi_users (
  id uuid primary key default gen_random_uuid(),
  display_name text not null,
  name_key text not null unique,
  password_salt text not null,
  password_hash text not null,
  balance bigint not null default 5000 check (balance >= 0),
  is_vip boolean not null default false,
  card_brand text not null check (card_brand in ('LPI NEON','LPI AURA','LPI ROYAL')),
  created_at timestamptz not null default now()
);

create table if not exists public.lpi_cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.lpi_users(id) on delete cascade,
  card_brand text not null check (card_brand in ('LPI NEON','LPI AURA','LPI ROYAL')),
  card_number text not null unique check (card_number ~ '^[0-9]{16}$'),
  cvv text not null check (cvv ~ '^[0-9]{3}$'),
  exp_month smallint not null check (exp_month between 1 and 12),
  exp_year smallint not null,
  created_at timestamptz not null default now()
);

create table if not exists public.lpi_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.lpi_users(id) on delete cascade,
  token_hash text not null unique,
  is_admin boolean not null default false,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists public.lpi_transfers (
  id uuid primary key default gen_random_uuid(),
  from_user_id uuid references public.lpi_users(id) on delete set null,
  to_user_id uuid references public.lpi_users(id) on delete set null,
  amount bigint not null check (amount > 0),
  payer_debit bigint not null default 0 check (payer_debit >= 0),
  discount bigint not null default 0 check (discount >= 0),
  cashback bigint not null default 0 check (cashback >= 0),
  cashback_percent smallint not null default 0 check (cashback_percent between 0 and 20),
  payment_method text not null default 'direct',
  note text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists lpi_transfers_from_created_idx on public.lpi_transfers(from_user_id, created_at desc);
create index if not exists lpi_transfers_to_created_idx on public.lpi_transfers(to_user_id, created_at desc);

create table if not exists public.lpi_payment_requests (
  id uuid primary key default gen_random_uuid(),
  receiver_user_id uuid not null references public.lpi_users(id) on delete cascade,
  payer_user_id uuid references public.lpi_users(id) on delete set null,
  amount bigint not null check (amount > 0),
  code_hash text not null unique,
  status text not null default 'pending' check (status in ('pending','paid','cancelled','expired')),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
create index if not exists lpi_requests_receiver_idx on public.lpi_payment_requests(receiver_user_id, status, created_at desc);

create table if not exists public.lpi_bills (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.lpi_users(id) on delete cascade,
  issued_by_user_id uuid references public.lpi_users(id) on delete set null,
  amount bigint not null check (amount > 0),
  memo text not null default 'City bill',
  status text not null default 'open' check (status in ('open','postponed','overdue','paid')),
  due_at timestamptz not null default (now() + interval '24 hours'),
  postponed_once boolean not null default false,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
create index if not exists lpi_bills_user_status_idx on public.lpi_bills(user_id, status, due_at);

create table if not exists public.lpi_announcements (
  id uuid primary key default gen_random_uuid(),
  message text not null,
  kind text not null default 'news' check (kind in ('news','vip','admin')),
  created_at timestamptz not null default now()
);
create index if not exists lpi_announcements_created_idx on public.lpi_announcements(created_at desc);

create table if not exists public.lpi_gift_cards (
  id uuid primary key default gen_random_uuid(),
  issuer_user_id uuid not null references public.lpi_users(id) on delete cascade,
  card_brand text not null check (card_brand in ('LPI NEON','LPI AURA','LPI ROYAL')),
  amount bigint not null check (amount > 0),
  code_hash text not null unique,
  redeemed_by uuid references public.lpi_users(id) on delete set null,
  redeemed_at timestamptz,
  expires_at timestamptz not null default (now() + interval '90 days'),
  created_at timestamptz not null default now()
);

create table if not exists public.lpi_sips (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.lpi_users(id) on delete cascade,
  amount smallint not null check (amount in (10,20,30)),
  active boolean not null default true,
  total_contributed bigint not null default 0 check (total_contributed >= 0),
  missed_payments integer not null default 0 check (missed_payments >= 0),
  next_due_date date not null default (current_date + 1),
  created_at timestamptz not null default now()
);
create index if not exists lpi_sips_due_idx on public.lpi_sips(user_id, active, next_due_date);

create table if not exists public.lpi_gold_market (
  id smallint primary key default 1 check (id = 1),
  price numeric(12,2) not null default 100.00 check (price > 0),
  updated_at timestamptz not null default now()
);
insert into public.lpi_gold_market(id, price) values (1, 100.00) on conflict (id) do nothing;

create table if not exists public.lpi_gold_holdings (
  user_id uuid primary key references public.lpi_users(id) on delete cascade,
  units numeric(14,3) not null default 0 check (units >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.lpi_gold_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.lpi_users(id) on delete cascade,
  side text not null check (side in ('buy','sell')),
  units numeric(14,3) not null check (units > 0),
  unit_price numeric(12,2) not null check (unit_price > 0),
  total_amount bigint not null check (total_amount > 0),
  created_at timestamptz not null default now()
);

create table if not exists public.lpi_api_keys (
  id uuid primary key default gen_random_uuid(),
  label text not null,
  key_hash text not null unique,
  key_last4 text not null,
  scopes text[] not null default array['balance']::text[],
  is_active boolean not null default true,
  created_by_user_id uuid references public.lpi_users(id) on delete set null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

create table if not exists public.lpi_api_audit (
  id uuid primary key default gen_random_uuid(),
  api_key_id uuid references public.lpi_api_keys(id) on delete set null,
  user_id uuid references public.lpi_users(id) on delete set null,
  action text not null,
  amount bigint,
  created_at timestamptz not null default now()
);

create table if not exists public.lpi_secrets (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

create or replace function public.lpi_check_admin_password(p_password text)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  select exists (
    select 1 from public.lpi_secrets
    where key = 'admin_password_hash'
      and value = extensions.crypt(p_password, value)
  );
$$;

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
begin
  if p_amount is null or p_amount <= 0 or p_amount > 100000000 then
    raise exception 'Enter a valid game-coin amount.';
  end if;
  if p_from = p_to then raise exception 'You cannot pay your own account.'; end if;
  select * into v_payer from public.lpi_users where id = p_from for update;
  if not found then raise exception 'Payer account not found.'; end if;
  select * into v_payee from public.lpi_users where id = p_to for update;
  if not found then raise exception 'Receiver account not found.'; end if;
  if v_payer.is_vip then v_discount := floor(p_amount * 0.03)::bigint; end if;
  v_debit := p_amount - v_discount;
  if v_payer.is_vip then
    v_pct := 1 + floor(random() * 20)::integer;
    v_cashback := floor(p_amount * v_pct / 100.0)::bigint;
  end if;
  if v_payer.balance < v_debit then raise exception 'Not enough LPI game coins.'; end if;
  update public.lpi_users set balance = balance - v_debit + v_cashback where id = p_from;
  update public.lpi_users set balance = balance + p_amount where id = p_to;
  insert into public.lpi_transfers(from_user_id,to_user_id,amount,payer_debit,discount,cashback,cashback_percent,payment_method)
  values (p_from,p_to,p_amount,v_debit,v_discount,v_cashback,v_pct,coalesce(nullif(p_method,''),'direct'))
  returning id into v_transfer_id;
  return jsonb_build_object('transfer_id',v_transfer_id,'amount',p_amount,'debit',v_debit,'discount',v_discount,'cashback',v_cashback,'cashback_percent',v_pct);
end;
$$;

create or replace function public.lpi_buy_vip(p_user_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user public.lpi_users%rowtype;
begin
  select * into v_user from public.lpi_users where id=p_user_id for update;
  if not found then raise exception 'Account not found.'; end if;
  if v_user.is_vip then raise exception 'This account already has VIP.'; end if;
  if v_user.balance < 1999 then raise exception 'VIP costs 1,999 LPI game coins.'; end if;
  update public.lpi_users set balance=balance-1999,is_vip=true where id=p_user_id;
  insert into public.lpi_transfers(from_user_id,amount,payer_debit,payment_method,note)
  values (p_user_id,1999,1999,'vip-purchase','VIP membership');
  insert into public.lpi_announcements(message,kind)
  values (v_user.display_name || ' has purchased VIP', 'vip');
  return jsonb_build_object('success',true,'cost',1999);
end;
$$;

create or replace function public.lpi_create_gift_card(p_issuer uuid, p_amount bigint, p_code_hash text, p_brand text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user public.lpi_users%rowtype;
  v_id uuid;
begin
  if p_amount is null or p_amount <= 0 or p_amount > 100000000 then raise exception 'Enter a valid amount.'; end if;
  select * into v_user from public.lpi_users where id=p_issuer for update;
  if not found then raise exception 'Account not found.'; end if;
  if p_brand <> v_user.card_brand then raise exception 'Gift cards can only use your own LPI card style.'; end if;
  if v_user.balance < p_amount then raise exception 'Not enough LPI game coins.'; end if;
  update public.lpi_users set balance=balance-p_amount where id=p_issuer;
  insert into public.lpi_gift_cards(issuer_user_id,card_brand,amount,code_hash)
  values(p_issuer,p_brand,p_amount,p_code_hash) returning id into v_id;
  insert into public.lpi_transfers(from_user_id,amount,payer_debit,payment_method,note)
  values(p_issuer,p_amount,p_amount,'gift-card-create','One-time gift card');
  return jsonb_build_object('gift_card_id',v_id,'amount',p_amount);
end;
$$;

create or replace function public.lpi_redeem_gift_card(p_user_id uuid, p_code_hash text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_card public.lpi_gift_cards%rowtype;
  v_user public.lpi_users%rowtype;
begin
  select * into v_user from public.lpi_users where id=p_user_id for update;
  if not found then raise exception 'Account not found.'; end if;
  select * into v_card from public.lpi_gift_cards
    where code_hash=p_code_hash and redeemed_at is null and expires_at > now()
    for update;
  if not found then raise exception 'Gift code is invalid, expired, or already used.'; end if;
  if v_card.card_brand <> v_user.card_brand then raise exception 'This gift card is for a different LPI card style.'; end if;
  update public.lpi_gift_cards set redeemed_by=p_user_id,redeemed_at=now() where id=v_card.id;
  update public.lpi_users set balance=balance+v_card.amount where id=p_user_id;
  insert into public.lpi_transfers(to_user_id,amount,payment_method,note)
  values(p_user_id,v_card.amount,'gift-card-redeem','Gift card redeemed');
  return jsonb_build_object('success',true,'amount',v_card.amount);
end;
$$;

create or replace function public.lpi_complete_payment_request(p_request_id uuid, p_payer_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_req public.lpi_payment_requests%rowtype;
  v_result jsonb;
begin
  select * into v_req from public.lpi_payment_requests where id=p_request_id for update;
  if not found or v_req.status <> 'pending' then raise exception 'This payment request is no longer pending.'; end if;
  if v_req.expires_at <= now() then
    update public.lpi_payment_requests set status='expired' where id=v_req.id;
    raise exception 'This request expired. Ask the receiver for a new code.';
  end if;
  if v_req.receiver_user_id=p_payer_id then raise exception 'You cannot pay your own request.'; end if;
  v_result := public.lpi_transfer(p_payer_id,v_req.receiver_user_id,v_req.amount,'tap-request');
  update public.lpi_payment_requests set status='paid',payer_user_id=p_payer_id,paid_at=now() where id=v_req.id;
  return v_result;
end;
$$;

create or replace function public.lpi_pay_bill(p_bill_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_bill public.lpi_bills%rowtype;
  v_user public.lpi_users%rowtype;
begin
  select * into v_bill from public.lpi_bills where id=p_bill_id and user_id=p_user_id for update;
  if not found or v_bill.status='paid' then raise exception 'This bill is already paid or unavailable.'; end if;
  select * into v_user from public.lpi_users where id=p_user_id for update;
  if v_user.balance < v_bill.amount then raise exception 'Not enough LPI game coins to pay this bill.'; end if;
  update public.lpi_users set balance=balance-v_bill.amount where id=p_user_id;
  update public.lpi_bills set status='paid',paid_at=now() where id=p_bill_id;
  insert into public.lpi_transfers(from_user_id,amount,payer_debit,payment_method,note)
  values(p_user_id,v_bill.amount,v_bill.amount,'bill-payment',v_bill.memo);
  return jsonb_build_object('success',true,'amount',v_bill.amount);
end;
$$;

create or replace function public.lpi_admin_grant(p_target_user_id uuid, p_amount bigint, p_note text default 'Admin coin grant')
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user public.lpi_users%rowtype;
begin
  if p_amount is null or p_amount <= 0 or p_amount > 100000000 then raise exception 'Enter a valid coin grant.'; end if;
  select * into v_user from public.lpi_users where id=p_target_user_id for update;
  if not found then raise exception 'Target account not found.'; end if;
  update public.lpi_users set balance=balance+p_amount where id=p_target_user_id;
  insert into public.lpi_transfers(to_user_id,amount,payment_method,note)
  values(p_target_user_id,p_amount,'admin-grant',left(coalesce(p_note,'Admin coin grant'),120));
  return jsonb_build_object('success',true,'granted',p_amount);
end;
$$;

create or replace function public.lpi_api_adjust(p_target_user_id uuid, p_amount bigint, p_mode text, p_api_key_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user public.lpi_users%rowtype;
begin
  if p_amount is null or p_amount <= 0 or p_amount > 100000000 then raise exception 'Enter a valid game-coin amount.'; end if;
  if p_mode not in ('deposit','withdraw') then raise exception 'Unsupported API operation.'; end if;
  select * into v_user from public.lpi_users where id=p_target_user_id for update;
  if not found then raise exception 'Target account not found.'; end if;
  if p_mode='withdraw' and v_user.balance < p_amount then raise exception 'Not enough LPI game coins.'; end if;
  if p_mode='deposit' then
    update public.lpi_users set balance=balance+p_amount where id=p_target_user_id;
    insert into public.lpi_transfers(to_user_id,amount,payment_method,note)
    values(p_target_user_id,p_amount,'api-deposit','Sandbox API deposit');
  else
    update public.lpi_users set balance=balance-p_amount where id=p_target_user_id;
    insert into public.lpi_transfers(from_user_id,amount,payer_debit,payment_method,note)
    values(p_target_user_id,p_amount,p_amount,'api-withdraw','Sandbox API withdrawal');
  end if;
  insert into public.lpi_api_audit(api_key_id,user_id,action,amount)
  values(p_api_key_id,p_target_user_id,p_mode,p_amount);
  return jsonb_build_object('success',true,'mode',p_mode,'amount',p_amount);
end;
$$;

create or replace function public.lpi_trade_gold(p_user_id uuid, p_units numeric, p_side text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user public.lpi_users%rowtype;
  v_market public.lpi_gold_market%rowtype;
  v_holding numeric(14,3) := 0;
  v_total bigint;
begin
  if p_units is null or p_units <= 0 or p_units > 10000 then raise exception 'Enter valid gold units.'; end if;
  if p_side not in ('buy','sell') then raise exception 'Choose buy or sell.'; end if;
  select * into v_market from public.lpi_gold_market where id=1 for update;
  select * into v_user from public.lpi_users where id=p_user_id for update;
  if not found then raise exception 'Account not found.'; end if;
  select units into v_holding from public.lpi_gold_holdings where user_id=p_user_id for update;
  if v_holding is null then v_holding := 0; end if;
  if p_side='buy' then
    v_total := ceil(v_market.price*p_units)::bigint;
    if v_user.balance < v_total then raise exception 'Not enough LPI game coins to buy gold.'; end if;
    update public.lpi_users set balance=balance-v_total where id=p_user_id;
    insert into public.lpi_gold_holdings(user_id,units,updated_at)
      values(p_user_id,p_units,now())
      on conflict(user_id) do update set units=public.lpi_gold_holdings.units+excluded.units,updated_at=now();
    insert into public.lpi_transfers(from_user_id,amount,payer_debit,payment_method,note)
      values(p_user_id,v_total,v_total,'gold-buy','Simulated gold purchase');
  else
    if v_holding < p_units then raise exception 'You do not own that many gold units.'; end if;
    v_total := greatest(1,floor(v_market.price*p_units)::bigint);
    update public.lpi_gold_holdings set units=units-p_units,updated_at=now() where user_id=p_user_id;
    update public.lpi_users set balance=balance+v_total where id=p_user_id;
    insert into public.lpi_transfers(to_user_id,amount,payment_method,note)
      values(p_user_id,v_total,'gold-sell','Simulated gold sale');
  end if;
  insert into public.lpi_gold_transactions(user_id,side,units,unit_price,total_amount)
    values(p_user_id,p_side,p_units,v_market.price,v_total);
  return jsonb_build_object('success',true,'side',p_side,'units',p_units,'unit_price',v_market.price,'total',v_total);
end;
$$;

create or replace function public.lpi_process_sips(p_user_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_plan public.lpi_sips%rowtype;
  v_user public.lpi_users%rowtype;
  v_paid integer := 0;
  v_missed integer := 0;
begin
  for v_plan in select * from public.lpi_sips where user_id=p_user_id and active=true and next_due_date<=current_date for update
  loop
    select * into v_user from public.lpi_users where id=p_user_id for update;
    if v_user.balance >= v_plan.amount then
      update public.lpi_users set balance=balance-v_plan.amount where id=p_user_id;
      update public.lpi_sips set total_contributed=total_contributed+v_plan.amount,next_due_date=current_date+1 where id=v_plan.id;
      insert into public.lpi_transfers(from_user_id,amount,payer_debit,payment_method,note)
      values(p_user_id,v_plan.amount,v_plan.amount,'sip-contribution','Daily game-coin SIP contribution');
      v_paid := v_paid + 1;
    else
      update public.lpi_sips set missed_payments=missed_payments+1,next_due_date=current_date+1 where id=v_plan.id;
      v_missed := v_missed + 1;
    end if;
  end loop;
  return jsonb_build_object('processed',v_paid,'missed',v_missed);
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'lpi_users','lpi_cards','lpi_sessions','lpi_transfers','lpi_payment_requests',
    'lpi_bills','lpi_announcements','lpi_gift_cards','lpi_sips','lpi_gold_market',
    'lpi_gold_holdings','lpi_gold_transactions','lpi_api_keys','lpi_api_audit','lpi_secrets'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from anon, authenticated', t);
    execute format('grant all on table public.%I to service_role', t);
  end loop;
end $$;

revoke all on function public.lpi_check_admin_password(text) from public, anon, authenticated;
revoke all on function public.lpi_transfer(uuid,uuid,bigint,text) from public, anon, authenticated;
revoke all on function public.lpi_buy_vip(uuid) from public, anon, authenticated;
revoke all on function public.lpi_create_gift_card(uuid,bigint,text,text) from public, anon, authenticated;
revoke all on function public.lpi_redeem_gift_card(uuid,text) from public, anon, authenticated;
revoke all on function public.lpi_complete_payment_request(uuid,uuid) from public, anon, authenticated;
revoke all on function public.lpi_pay_bill(uuid,uuid) from public, anon, authenticated;
revoke all on function public.lpi_admin_grant(uuid,bigint,text) from public, anon, authenticated;
revoke all on function public.lpi_api_adjust(uuid,bigint,text,uuid) from public, anon, authenticated;
revoke all on function public.lpi_trade_gold(uuid,numeric,text) from public, anon, authenticated;
revoke all on function public.lpi_process_sips(uuid) from public, anon, authenticated;

grant execute on function public.lpi_check_admin_password(text) to service_role;
grant execute on function public.lpi_transfer(uuid,uuid,bigint,text) to service_role;
grant execute on function public.lpi_buy_vip(uuid) to service_role;
grant execute on function public.lpi_create_gift_card(uuid,bigint,text,text) to service_role;
grant execute on function public.lpi_redeem_gift_card(uuid,text) to service_role;
grant execute on function public.lpi_complete_payment_request(uuid,uuid) to service_role;
grant execute on function public.lpi_pay_bill(uuid,uuid) to service_role;
grant execute on function public.lpi_admin_grant(uuid,bigint,text) to service_role;
grant execute on function public.lpi_api_adjust(uuid,bigint,text,uuid) to service_role;
grant execute on function public.lpi_trade_gold(uuid,numeric,text) to service_role;
grant execute on function public.lpi_process_sips(uuid) to service_role;
