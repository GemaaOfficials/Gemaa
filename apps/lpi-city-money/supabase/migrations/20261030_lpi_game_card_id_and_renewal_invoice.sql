-- LPI City Money v0.4.0
-- Replace simulated payment-card credentials with a public game-only player ID.
alter table public.lpi_cards add column if not exists card_id text;
update public.lpi_cards
set card_id = 'LPI-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))
where card_id is null;
alter table public.lpi_cards alter column card_id set not null;
create unique index if not exists lpi_cards_card_id_unique on public.lpi_cards(card_id);
alter table public.lpi_cards drop column if exists card_number, drop column if exists cvv;

-- One pending renewal invoice per player. It is denominated in LPI game coins.
create unique index if not exists lpi_bills_one_pending_card_renewal
on public.lpi_bills(user_id)
where memo = 'LPI CityCard renewal · 500 LPI game coins' and status <> 'paid';

create or replace function public.lpi_ensure_card_renewal_bill(p_user_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_card public.lpi_cards%rowtype;
  v_bill_id uuid;
  v_expiry date;
begin
  select * into v_card from public.lpi_cards where user_id = p_user_id;
  if not found then return null; end if;

  v_expiry := (make_date(v_card.exp_year::int, v_card.exp_month::int, 1)
    + interval '1 month' - interval '1 day')::date;
  if v_expiry >= current_date then return null; end if;

  select id into v_bill_id
  from public.lpi_bills
  where user_id = p_user_id
    and memo = 'LPI CityCard renewal · 500 LPI game coins'
    and status <> 'paid'
  order by created_at desc limit 1;

  if v_bill_id is not null then return v_bill_id; end if;

  insert into public.lpi_bills(user_id, issued_by_user_id, amount, memo, due_at)
  values (p_user_id, null, 500, 'LPI CityCard renewal · 500 LPI game coins', now() + interval '7 days')
  returning id into v_bill_id;
  return v_bill_id;
exception when unique_violation then
  select id into v_bill_id
  from public.lpi_bills
  where user_id = p_user_id
    and memo = 'LPI CityCard renewal · 500 LPI game coins'
    and status <> 'paid'
  order by created_at desc limit 1;
  return v_bill_id;
end;
$function$;

-- Player confirmation is required: the bill is paid from the in-game balance.
-- Only after the 500 LPI bill is paid is the game-card expiry extended.
create or replace function public.lpi_pay_bill(p_bill_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_bill public.lpi_bills%rowtype;
  v_user public.lpi_users%rowtype;
  v_next_month date;
  v_card_renewed boolean := false;
begin
  select * into v_bill from public.lpi_bills
  where id = p_bill_id and user_id = p_user_id for update;
  if not found or v_bill.status = 'paid' then
    raise exception 'This bill is already paid or unavailable.';
  end if;

  select * into v_user from public.lpi_users where id = p_user_id for update;
  if v_user.balance < v_bill.amount then
    raise exception 'Not enough LPI game coins to pay this bill.';
  end if;

  update public.lpi_users set balance = balance - v_bill.amount where id = p_user_id;
  update public.lpi_bills set status = 'paid', paid_at = now() where id = p_bill_id;
  insert into public.lpi_transfers(from_user_id, amount, payer_debit, payment_method, note)
  values (p_user_id, v_bill.amount, v_bill.amount, 'bill-payment', v_bill.memo);

  if v_bill.memo = 'LPI CityCard renewal · 500 LPI game coins' then
    v_next_month := (date_trunc('month', now()) + interval '24 months')::date;
    update public.lpi_cards
    set exp_month = extract(month from v_next_month)::smallint,
        exp_year = extract(year from v_next_month)::smallint
    where user_id = p_user_id;
    if not found then
      raise exception 'CityCard renewal could not be completed because the player card is missing.';
    end if;
    v_card_renewed := true;
  end if;

  return jsonb_build_object('success', true, 'amount', v_bill.amount, 'cardRenewed', v_card_renewed);
end;
$function$;
