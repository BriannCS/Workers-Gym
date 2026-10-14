-- Hecho por Briann$ Workers Corp.
-- Núcleo del sistema: personal, planes, clientes, pagos y asistencia.
-- Dinero en centavos (integer). Solo el personal registrado en public.staff
-- puede leer o escribir: estar autenticado no basta (el registro público de
-- Supabase podría estar abierto).

-- ---------------------------------------------------------------------------
-- Personal

create table public.staff (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  full_name  text not null check (length(trim(full_name)) > 0),
  created_at timestamptz not null default now()
);

create schema if not exists private;

-- Security definer para consultar staff sin recursión de RLS. Vive en un
-- esquema no expuesto por la Data API y solo mira al usuario que llama.
create function private.is_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.staff where user_id = (select auth.uid()));
$$;

revoke all on function private.is_staff() from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.is_staff() to authenticated;

-- ---------------------------------------------------------------------------
-- Tablas

create table public.plans (
  id            uuid primary key default gen_random_uuid(),
  name          text not null check (length(trim(name)) > 0),
  price_cents   integer not null check (price_cents >= 0),
  duration_days integer not null check (duration_days > 0),
  active        boolean not null default true,
  created_at    timestamptz not null default now()
);

create table public.members (
  id          uuid primary key default gen_random_uuid(),
  full_name   text not null check (length(trim(full_name)) > 0),
  document_id text unique,
  phone       text,
  email       text,
  notes       text,
  created_at  timestamptz not null default now()
);

create table public.payments (
  id           uuid primary key default gen_random_uuid(),
  member_id    uuid not null references public.members (id),
  plan_id      uuid not null references public.plans (id),
  -- Copia del precio al momento del pago: cambiar el plan no altera el historial.
  amount_cents integer not null check (amount_cents >= 0),
  method       text not null check (method in ('efectivo', 'transferencia', 'tarjeta', 'otro')),
  -- Periodo cubierto, ambos días inclusive.
  period_start date not null,
  period_end   date not null check (period_end >= period_start),
  paid_at      timestamptz not null default now(),
  created_by   uuid default auth.uid(),
  -- Los pagos no se borran: se anulan dejando rastro.
  voided_at    timestamptz,
  voided_by    uuid,
  void_reason  text,
  check ((voided_at is null) = (void_reason is null))
);
create index payments_member_period_idx on public.payments (member_id, period_end desc) where voided_at is null;
create index payments_plan_id_idx on public.payments (plan_id);
create index payments_paid_at_idx on public.payments (paid_at desc);

create table public.attendance (
  id            uuid primary key default gen_random_uuid(),
  member_id     uuid not null references public.members (id),
  checked_in_at timestamptz not null default now(),
  method        text not null default 'manual' check (method in ('manual', 'huella', 'qr')),
  created_by    uuid default auth.uid()
);
create index attendance_member_id_idx on public.attendance (member_id);
create index attendance_checked_in_idx on public.attendance (checked_in_at desc);

-- Clientes con su último vencimiento (ignorando pagos anulados).
create view public.member_overview
with (security_invoker = true) as
select
  m.*,
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
) last_payment on true;

-- ---------------------------------------------------------------------------
-- Operaciones de pago (el servidor calcula monto y periodo)

-- p_today es la fecha local de la recepción (el servidor está en UTC).
create function public.register_payment(p_member_id uuid, p_plan_id uuid, p_method text, p_today date)
returns public.payments
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_plan    public.plans;
  v_last    date;
  v_start   date;
  v_payment public.payments;
begin
  select * into v_plan from public.plans where id = p_plan_id and active;
  if not found then
    raise exception 'El plan no existe o está archivado' using errcode = 'P0002';
  end if;

  -- Bloquea al cliente para que dos cobros simultáneos no calculen el mismo periodo.
  perform 1 from public.members where id = p_member_id for update;
  if not found then
    raise exception 'El cliente no existe' using errcode = 'P0002';
  end if;

  select max(period_end) into v_last
  from public.payments
  where member_id = p_member_id and voided_at is null;

  -- Vigente: continúa al día siguiente del vencimiento. Vencida o nueva: empieza hoy.
  v_start := case when v_last is not null and v_last >= p_today then v_last + 1 else p_today end;

  insert into public.payments (member_id, plan_id, amount_cents, method, period_start, period_end)
  values (p_member_id, p_plan_id, v_plan.price_cents, p_method, v_start, v_start + v_plan.duration_days - 1)
  returning * into v_payment;

  return v_payment;
end;
$$;

create function public.void_payment(p_payment_id uuid, p_reason text)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception 'Indica el motivo de la anulación' using errcode = '22023';
  end if;
  update public.payments
  set voided_at = now(), voided_by = (select auth.uid()), void_reason = trim(p_reason)
  where id = p_payment_id and voided_at is null;
  if not found then
    raise exception 'El pago no existe o ya estaba anulado' using errcode = 'P0002';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Permisos: nada para anon; el personal opera según la tabla.

revoke all on public.staff, public.plans, public.members, public.payments, public.attendance, public.member_overview
  from anon, authenticated;

grant select on public.staff to authenticated;
grant select, insert, update on public.plans, public.members to authenticated;
grant select on public.payments, public.member_overview to authenticated;
-- La app crea/anula pagos con las funciones de arriba; al ser security invoker
-- necesitan estos permisos. Solo las columnas de anulación son modificables.
grant insert on public.payments to authenticated;
grant update (voided_at, voided_by, void_reason) on public.payments to authenticated;
grant select, insert, delete on public.attendance to authenticated;

revoke all on function public.register_payment(uuid, uuid, text, date) from public, anon;
revoke all on function public.void_payment(uuid, text) from public, anon;
grant execute on function public.register_payment(uuid, uuid, text, date) to authenticated;
grant execute on function public.void_payment(uuid, text) to authenticated;

alter table public.staff      enable row level security;
alter table public.plans      enable row level security;
alter table public.members    enable row level security;
alter table public.payments   enable row level security;
alter table public.attendance enable row level security;

create policy "staff_read_self" on public.staff
  for select to authenticated using (user_id = (select auth.uid()));

create policy "staff_only" on public.plans
  for all to authenticated using ((select private.is_staff())) with check ((select private.is_staff()));
create policy "staff_only" on public.members
  for all to authenticated using ((select private.is_staff())) with check ((select private.is_staff()));
create policy "staff_only" on public.payments
  for all to authenticated using ((select private.is_staff())) with check ((select private.is_staff()));
create policy "staff_only" on public.attendance
  for all to authenticated using ((select private.is_staff())) with check ((select private.is_staff()));
