-- Hecho por Briann$ Workers Corp.
-- Clientes: activo/inactivo, eliminar y foto visible.
--
-- 1. La vista member_overview se creó con `m.*` ANTES de existir photo_path;
--    Postgres fija las columnas de una vista al crearla, así que la foto se
--    guardaba pero la app nunca recibía la ruta. Se recrea con columnas
--    explícitas.
-- 2. Activo/inactivo: lo decide recepción; cobrarle a un inactivo lo reactiva.
-- 3. Eliminar = ocultar (deleted_at). El cliente sale de la planilla pero sus
--    pagos, ventas y asistencias siguen en la caja y el historial.

alter table public.members
  add column active boolean not null default true,
  add column deleted_at timestamptz,
  add column deleted_by uuid;

-- La cédula solo debe ser única entre clientes no eliminados (si alguien
-- vuelve después de eliminarlo, se registra de nuevo).
alter table public.members drop constraint members_document_id_key;
create unique index members_document_id_key on public.members (document_id) where deleted_at is null;

drop view public.member_overview;
create view public.member_overview
with (security_invoker = true) as
select
  m.id,
  m.full_name,
  m.document_id,
  m.phone,
  m.email,
  m.notes,
  m.photo_path,
  m.active,
  m.created_at,
  last_payment.period_end as expires_on,
  last_payment.plan_name
from public.members m
left join lateral (
  select p.period_end, pl.name as plan_name
  from public.payments p
  join public.plans pl on pl.id = p.plan_id
  where p.member_id = m.id and p.voided_at is null
  order by p.period_end desc
  limit 1
) last_payment on true
where m.deleted_at is null;

revoke all on public.member_overview from anon, authenticated;
grant select on public.member_overview to authenticated;

-- Activo/inactivo se edita directo; eliminar solo con la función (deja autor).
grant update (active) on public.members to authenticated;

-- ---------------------------------------------------------------------------
-- Eliminar cliente. Devuelve la ruta de la foto para que la app la borre del
-- almacenamiento.

create function public.delete_member(p_member_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_photo text;
begin
  perform private.assert_staff();

  select photo_path into v_photo from public.members
  where id = p_member_id and deleted_at is null
  for update;
  if not found then
    raise exception 'El cliente no existe o ya fue eliminado' using errcode = 'P0002';
  end if;

  update public.members
  set deleted_at = now(), deleted_by = (select auth.uid()), active = false, photo_path = null
  where id = p_member_id;
  return v_photo;
end;
$$;

revoke all on function public.delete_member(uuid) from public, anon;
grant execute on function public.delete_member(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Cobro: no a clientes eliminados y reactiva al inactivo que vuelve a pagar.
-- (Igual que en 20261014000000_security_hardening salvo esas dos reglas.)

create or replace function public.register_payment(
  p_member_id uuid, p_plan_id uuid, p_method text, p_today date,
  p_rate numeric default null, p_rate_source text default null
)
returns public.payments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plan     public.plans;
  v_currency text;
  v_last     date;
  v_start    date;
  v_payment  public.payments;
begin
  perform private.assert_staff();

  if p_today is null or p_today < current_date - 1 or p_today > current_date + 1 then
    raise exception 'Fecha de cobro inválida' using errcode = '22023';
  end if;

  select * into v_plan from public.plans where id = p_plan_id and active;
  if not found then
    raise exception 'El plan no existe o está archivado' using errcode = 'P0002';
  end if;

  select currency into v_currency from public.payment_methods where code = p_method and active;
  if not found then
    raise exception 'El método de pago no existe o está desactivado' using errcode = 'P0002';
  end if;
  if v_currency = 'VES' then
    perform private.assert_valid_rate(p_rate, p_rate_source);
  end if;

  perform 1 from public.members where id = p_member_id and deleted_at is null for update;
  if not found then
    raise exception 'El cliente no existe' using errcode = 'P0002';
  end if;

  select max(period_end) into v_last
  from public.payments
  where member_id = p_member_id and voided_at is null;

  v_start := case when v_last is not null and v_last >= p_today then v_last + 1 else p_today end;

  insert into public.payments (
    member_id, plan_id, amount_cents, method, period_start, period_end,
    currency, rate, rate_source, amount_ves_cents, created_by
  )
  values (
    p_member_id, p_plan_id, v_plan.price_cents, p_method, v_start, v_start + v_plan.duration_days - 1,
    v_currency,
    case when v_currency = 'VES' then p_rate end,
    case when v_currency = 'VES' then p_rate_source end,
    case when v_currency = 'VES' then round(v_plan.price_cents * p_rate) end,
    (select auth.uid())
  )
  returning * into v_payment;

  update public.members set active = true where id = p_member_id and not active;

  return v_payment;
end;
$$;
