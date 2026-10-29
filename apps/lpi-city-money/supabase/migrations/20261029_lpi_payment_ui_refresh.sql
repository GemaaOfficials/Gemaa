-- LPI City Money v0.3.0 play-wallet support. No real bank or UPI rails.
-- Make the spin configuration table self-initializing for fresh deployments.
create table if not exists public.lpi_spin_config (
  id integer primary key default 1 check (id = 1),
  reward_config jsonb not null default '[{"type":"coins","amount":10,"label":"10 LPI bonus coins","weight":3},{"type":"coins","amount":20,"label":"20 LPI bonus coins","weight":3},{"type":"coins","amount":30,"label":"30 LPI bonus coins","weight":3},{"type":"cashback","amount":20,"label":"20% cashback coupon","weight":1},{"type":"vip","amount":10,"label":"10-minute VIP pass","weight":1}]'::jsonb,
  enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.lpi_users(id) on delete set null
);
alter table public.lpi_spin_config add column if not exists enabled boolean not null default false;
alter table public.lpi_spin_config alter column enabled set default false;
alter table public.lpi_gift_cards add column if not exists code_display text;
insert into public.lpi_spin_config (id, enabled)
values (1, false)
on conflict (id) do nothing;
-- Gift-card style is cosmetic. Any LPI player may redeem regardless of CityCard style.
create or replace function public.lpi_create_gift_card(p_issuer uuid, p_amount bigint, p_code_hash text, p_brand text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare v_user public.lpi_users%rowtype; v_id uuid;
begin
 if p_amount is null or p_amount <= 0 or p_amount > 100000000 then raise exception 'Enter a valid amount.'; end if;
 if p_brand not in ('LPI NEON','LPI AURA','LPI ROYAL') then raise exception 'Choose a valid LPI gift-card style.'; end if;
 select * into v_user from public.lpi_users where id=p_issuer for update;
 if not found then raise exception 'Account not found.'; end if;
 if v_user.balance < p_amount then raise exception 'Not enough LPI game coins.'; end if;
 update public.lpi_users set balance=balance-p_amount where id=p_issuer;
 insert into public.lpi_gift_cards(issuer_user_id,card_brand,amount,code_hash) values(p_issuer,p_brand,p_amount,p_code_hash) returning id into v_id;
 insert into public.lpi_transfers(from_user_id,amount,payer_debit,payment_method,note) values(p_issuer,p_amount,p_amount,'gift-card-create','One-time gift card');
 return jsonb_build_object('gift_card_id',v_id,'amount',p_amount);
end; $$;
create or replace function public.lpi_redeem_gift_card(p_user_id uuid, p_code_hash text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare v_card public.lpi_gift_cards%rowtype; v_user public.lpi_users%rowtype;
begin
 select * into v_user from public.lpi_users where id=p_user_id for update;
 if not found then raise exception 'Account not found.'; end if;
 select * into v_card from public.lpi_gift_cards where code_hash=p_code_hash and redeemed_at is null and expires_at > now() for update;
 if not found then raise exception 'Gift code is invalid, expired, or already used.'; end if;
 update public.lpi_gift_cards set redeemed_by=p_user_id,redeemed_at=now() where id=v_card.id;
 update public.lpi_users set balance=balance+v_card.amount where id=p_user_id;
 insert into public.lpi_transfers(to_user_id,amount,payment_method,note) values(p_user_id,v_card.amount,'gift-card-redeem','Gift card redeemed');
 return jsonb_build_object('success',true,'amount',v_card.amount);
end; $$;
