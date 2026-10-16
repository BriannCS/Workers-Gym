-- Hecho por Briann$ - Workers Corp.
-- Control de personal y roles (ver docs/control_de_personal.md).
--
-- Antes: cualquier cuenta de `staff` podía hacer todo.
-- Ahora: cada cuenta tiene un rol (dueño, administrador, recepción,
-- entrenador) y los permisos se comprueban EN EL SERVIDOR:
--   * Lecturas: políticas RLS con private.can().
--   * Escrituras: triggers en cada tabla. Como corren también dentro de las
--     funciones SECURITY DEFINER (cobros, ventas, compras), ningún camino
--     (app, API directa o función) se salta el rol.
-- Suspender una cuenta la bloquea al instante en todas las tablas.
-- La cuenta que ya existía pasa a ser Dueño: nadie pierde acceso.

-- ---------------------------------------------------------------------------
-- 1. Personal: rol, estado y datos de la ficha

alter table public.staff
  add column role          text not null default 'reception',
  add column status        text not null default 'active',
  add column document_id   text,
  add column phone         text,
  add column email         text,
  add column hired_on      date not null default current_date,
  add column terminated_on date,
  add column notes         text,
  add column updated_at    timestamptz not null default now();

update public.staff set role = 'owner';

alter table public.staff
  add constraint staff_role_check check (role in ('owner', 'admin', 'reception', 'trainer')),
  add constraint staff_status_check check (status in ('active', 'suspended', 'terminated')),
  add constraint staff_full_name_len check (char_length(full_name) between 2 and 120),
  add constraint staff_document_format check (document_id ~ '^[VE]-[0-9]{6,9}$'),
  add constraint staff_phone_format check (phone ~ '^[0-9]{10,11}$'),
  add constraint staff_email_format check (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' and char_length(email) <= 120),
  add constraint staff_notes_len check (char_length(notes) <= 2000);

create unique index staff_document_id_key on public.staff (document_id) where document_id is not null;

-- ---------------------------------------------------------------------------
-- 2. Catálogo de permisos y permisos por rol. El dueño los tiene todos
--    siempre (no se guardan), así nunca puede quedarse fuera.

create table public.permissions (
  code     text primary key,
  label    text not null,
  module   text not null,
  position integer not null
);

insert into public.permissions (code, label, module, position) values
  ('dashboard.money',   'Ver montos en Inicio',                  'Inicio',     10),
  ('attendance.create', 'Registrar entradas de clientes',        'Asistencia', 20),
  ('members.view',      'Ver clientes',                          'Clientes',   30),
  ('members.edit',      'Crear y editar clientes',               'Clientes',   31),
  ('members.delete',    'Desactivar y eliminar clientes',        'Clientes',   32),
  ('payments.view',     'Ver pagos e historial de cobros',       'Pagos',      40),
  ('payments.create',   'Cobrar membresías',                     'Pagos',      41),
  ('payments.void',     'Anular pagos',                          'Pagos',      42),
  ('store.sell',        'Vender en la tienda',                   'Tienda',     50),
  ('sales.void',        'Anular ventas',                         'Tienda',     51),
  ('inventory.view',    'Ver inventario y compras',              'Inventario', 60),
  ('inventory.manage',  'Productos, proveedores, compras y stock','Inventario', 61),
  ('cash.own',          'Ver su propia caja',                    'Caja',       70),
  ('cash.all',          'Ver la caja de todos y el cierre Z',    'Caja',       71),
  ('plans.manage',      'Crear y editar planes y precios',       'Planes',     80),
  ('settings.manage',   'Tasa de cambio y métodos de pago',      'Ajustes',    90),
  ('staff.view',        'Ver al personal',                       'Personal',  100),
  ('staff.manage',      'Crear, editar y suspender personal',    'Personal',  101),
  ('roles.manage',      'Cambiar los permisos de cada rol',      'Personal',  102),
  ('audit.view',        'Ver la bitácora de actividad',          'Personal',  103);

create table public.role_permissions (
  role       text not null check (role in ('admin', 'reception', 'trainer')),
  permission text not null references public.permissions (code) on delete cascade,
  primary key (role, permission)
);

insert into public.role_permissions (role, permission)
select 'admin', code from public.permissions where code <> 'roles.manage';

insert into public.role_permissions (role, permission) values
  ('reception', 'dashboard.money'),
  ('reception', 'attendance.create'),
  ('reception', 'members.view'),
  ('reception', 'members.edit'),
  ('reception', 'payments.view'),
  ('reception', 'payments.create'),
  ('reception', 'store.sell'),
  ('reception', 'inventory.view'),
  ('reception', 'cash.own'),
  ('trainer',   'attendance.create'),
  ('trainer',   'members.view');

-- ---------------------------------------------------------------------------
-- 3. Funciones de seguridad (esquema privado, no expuesto por la API)

-- Solo cuentas ACTIVAS. Todas las políticas existentes usan esta función, así
-- que suspender a alguien lo bloquea al instante en todas las tablas.
create or replace function private.is_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.staff
    where user_id = (select auth.uid()) and status = 'active'
  );
$$;

create function private.staff_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select role from public.staff where user_id = (select auth.uid()) and status = 'active';
$$;

create function private.can(p_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.staff s
    where s.user_id = (select auth.uid())
      and s.status = 'active'
      and (
        s.role = 'owner'
        or exists (select 1 from public.role_permissions rp where rp.role = s.role and rp.permission = p_permission)
      )
  );
$$;

-- Llamadas sin usuario de la app (panel de Supabase, migraciones, la clave de
-- servicio de las Edge Functions) no pasan por roles. Las de `anon` o de un
-- usuario sí.
create function private.is_backend()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is null
     and coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') not in ('anon', 'authenticated');
$$;

create function private.assert_can(p_permission text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if private.is_backend() then
    return;
  end if;
  if not private.can(p_permission) then
    raise exception 'Tu rol no tiene permiso para esta acción (%)', p_permission using errcode = '42501';
  end if;
end;
$$;

-- Bitácora: solo se escribe desde el servidor.
create table public.audit_log (
  id        bigint generated always as identity primary key,
  at        timestamptz not null default now(),
  user_id   uuid default auth.uid(),
  action    text not null,
  entity    text not null,
  entity_id text,
  detail    jsonb not null default '{}'::jsonb
);
create index audit_log_at_idx on public.audit_log (at desc);
create index audit_log_user_idx on public.audit_log (user_id, at desc);

create function private.audit(p_action text, p_entity text, p_entity_id text, p_detail jsonb default '{}'::jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.audit_log (user_id, action, entity, entity_id, detail)
  values ((select auth.uid()), p_action, p_entity, p_entity_id, coalesce(p_detail, '{}'::jsonb));
$$;

revoke all on function private.staff_role() from public, anon;
revoke all on function private.can(text) from public, anon;
revoke all on function private.is_backend() from public, anon, authenticated;
revoke all on function private.assert_can(text) from public, anon, authenticated;
revoke all on function private.audit(text, text, text, jsonb) from public, anon, authenticated;
grant execute on function private.staff_role() to authenticated;
grant execute on function private.can(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Permisos de escritura por tabla (triggers)

-- Pagos: cobrar y anular.
create function private.guard_payments()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform private.assert_can('payments.create');
  elsif old.voided_at is null and new.voided_at is not null then
    perform private.assert_can('payments.void');
    perform private.audit('payment.void', 'payments', new.id::text,
      jsonb_build_object('amount_cents', new.amount_cents, 'reason', new.void_reason, 'member_id', new.member_id));
  end if;
  return new;
end;
$$;
create trigger guard_payments before insert or update on public.payments
  for each row execute function private.guard_payments();

-- Ventas: vender y anular.
create function private.guard_sales()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform private.assert_can('store.sell');
  elsif old.voided_at is null and new.voided_at is not null then
    perform private.assert_can('sales.void');
    perform private.audit('sale.void', 'sales', new.id::text,
      jsonb_build_object('total_cents', new.total_cents, 'reason', new.void_reason));
  end if;
  return new;
end;
$$;
create trigger guard_sales before insert or update on public.sales
  for each row execute function private.guard_sales();

-- Compras y ajustes de stock.
create function private.guard_purchases()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform private.assert_can('inventory.manage');
  elsif old.voided_at is null and new.voided_at is not null then
    perform private.assert_can('inventory.manage');
    perform private.audit('purchase.void', 'purchases', new.id::text,
      jsonb_build_object('total_cents', new.total_cents, 'reason', new.void_reason));
  end if;
  return new;
end;
$$;
create trigger guard_purchases before insert or update on public.purchases
  for each row execute function private.guard_purchases();

create function private.guard_stock_entries()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.assert_can('inventory.manage');
  perform private.audit('stock.adjust', 'products', new.product_id::text,
    jsonb_build_object('quantity', new.quantity, 'note', new.note));
  return new;
end;
$$;
create trigger guard_stock_entries before insert on public.stock_entries
  for each row execute function private.guard_stock_entries();

-- Productos: los datos los edita inventario; el stock lo mueven ventas y
-- compras (que ya tienen su propio permiso).
create function private.guard_products()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT'
     or (new.name, new.sku, new.price_cents, new.min_stock, new.supplier_id, new.active)
        is distinct from (old.name, old.sku, old.price_cents, old.min_stock, old.supplier_id, old.active) then
    perform private.assert_can('inventory.manage');
  end if;
  if tg_op = 'UPDATE' and new.price_cents is distinct from old.price_cents then
    perform private.audit('product.price', 'products', new.id::text,
      jsonb_build_object('name', new.name, 'from', old.price_cents, 'to', new.price_cents));
  end if;
  return new;
end;
$$;
create trigger guard_products before insert or update on public.products
  for each row execute function private.guard_products();

create function private.guard_suppliers()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.assert_can('inventory.manage');
  return new;
end;
$$;
create trigger guard_suppliers before insert or update on public.suppliers
  for each row execute function private.guard_suppliers();

-- Planes y precios.
create function private.guard_plans()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.assert_can('plans.manage');
  perform private.audit(case tg_op when 'INSERT' then 'plan.create' else 'plan.update' end, 'plans', new.id::text,
    jsonb_build_object('name', new.name, 'price_cents', new.price_cents, 'duration_days', new.duration_days, 'active', new.active,
                       'previous_price_cents', case when tg_op = 'UPDATE' then old.price_cents end));
  return new;
end;
$$;
create trigger guard_plans before insert or update on public.plans
  for each row execute function private.guard_plans();

-- Ajustes: tasa y métodos de pago.
create function private.guard_settings()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.assert_can('settings.manage');
  perform private.audit('settings.update', tg_table_name, null, to_jsonb(new));
  return new;
end;
$$;
create trigger guard_settings before update on public.settings
  for each row execute function private.guard_settings();
create trigger guard_payment_methods before insert or update on public.payment_methods
  for each row execute function private.guard_settings();

-- Clientes: crear/editar, y por separado desactivar/eliminar. Reactivar (lo
-- hace el cobro a un inactivo) cuenta como editar.
create function private.guard_members()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform private.assert_can('members.edit');
    return new;
  end if;
  if old.deleted_at is null and new.deleted_at is not null then
    perform private.assert_can('members.delete');
    perform private.audit('member.delete', 'members', new.id::text, jsonb_build_object('name', new.full_name));
  elsif old.active and not new.active then
    perform private.assert_can('members.delete');
    perform private.audit('member.deactivate', 'members', new.id::text, jsonb_build_object('name', new.full_name));
  else
    perform private.assert_can('members.edit');
  end if;
  return new;
end;
$$;
create trigger guard_members before insert or update on public.members
  for each row execute function private.guard_members();

-- Asistencia de clientes.
create function private.guard_attendance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.assert_can('attendance.create');
  return new;
end;
$$;
create trigger guard_attendance before insert on public.attendance
  for each row execute function private.guard_attendance();

-- Funciones que corrían sin pasar por una tabla protegida: eliminar cliente
-- ya pasa por guard_members. Nada más que tocar.

-- ---------------------------------------------------------------------------
-- 5. Lecturas por permiso (RLS). Lo demás sigue en "staff_only".

drop policy "staff_only" on public.payments;
create policy "payments_read" on public.payments
  for select to authenticated using ((select private.can('payments.view')));

drop policy "staff_only" on public.sales;
create policy "sales_read" on public.sales
  for select to authenticated using ((select private.can('store.sell')) or (select private.can('cash.all')));
drop policy "staff_only" on public.sale_items;
create policy "sale_items_read" on public.sale_items
  for select to authenticated using ((select private.can('store.sell')) or (select private.can('cash.all')));

drop policy "staff_only" on public.purchases;
create policy "purchases_read" on public.purchases
  for select to authenticated using ((select private.can('inventory.view')));
drop policy "staff_only" on public.purchase_items;
create policy "purchase_items_read" on public.purchase_items
  for select to authenticated using ((select private.can('inventory.view')));
drop policy "staff_only" on public.stock_entries;
create policy "stock_entries_read" on public.stock_entries
  for select to authenticated using ((select private.can('inventory.view')));

-- El personal se ve a sí mismo; con staff.view, a todos. Se escribe solo con
-- las funciones de abajo (y la Edge Function staff-admin).
drop policy "staff_read_self" on public.staff;
create policy "staff_read" on public.staff
  for select to authenticated
  using (user_id = (select auth.uid()) or (select private.can('staff.view')));

alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.audit_log enable row level security;
create policy "permissions_read" on public.permissions
  for select to authenticated using ((select private.is_staff()));
create policy "role_permissions_read" on public.role_permissions
  for select to authenticated using ((select private.is_staff()));
create policy "audit_read" on public.audit_log
  for select to authenticated using ((select private.can('audit.view')));

revoke all on public.permissions, public.role_permissions, public.audit_log from anon, authenticated;
grant select on public.permissions, public.role_permissions, public.audit_log to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Turnos y marcaje (entrada/salida) del personal

create table public.staff_shifts (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid not null references public.staff (user_id) on delete cascade,
  weekday   smallint not null check (weekday between 1 and 7), -- 1 = lunes
  starts_at time not null,
  ends_at   time not null,
  check (ends_at > starts_at)
);
create index staff_shifts_user_idx on public.staff_shifts (user_id, weekday);

create table public.staff_time_entries (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid not null references public.staff (user_id) on delete cascade,
  clock_in  timestamptz not null default now(),
  clock_out timestamptz,
  check (clock_out is null or clock_out >= clock_in)
);
create index staff_time_entries_user_idx on public.staff_time_entries (user_id, clock_in desc);
-- Una sola jornada abierta por persona.
create unique index staff_time_entries_open_key on public.staff_time_entries (user_id) where clock_out is null;

alter table public.staff_shifts enable row level security;
alter table public.staff_time_entries enable row level security;

create policy "shifts_read" on public.staff_shifts
  for select to authenticated using (user_id = (select auth.uid()) or (select private.can('staff.view')));
create policy "shifts_write" on public.staff_shifts
  for all to authenticated using ((select private.can('staff.manage'))) with check ((select private.can('staff.manage')));

create policy "time_entries_read" on public.staff_time_entries
  for select to authenticated using (user_id = (select auth.uid()) or (select private.can('staff.view')));

revoke all on public.staff_shifts, public.staff_time_entries from anon, authenticated;
grant select, insert, update, delete on public.staff_shifts to authenticated;
grant select on public.staff_time_entries to authenticated;

-- Marcar entrada o salida (hora del servidor). Devuelve la jornada.
create function public.staff_clock()
returns public.staff_time_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry public.staff_time_entries;
begin
  perform private.assert_staff();
  update public.staff_time_entries
  set clock_out = now()
  where user_id = (select auth.uid()) and clock_out is null
  returning * into v_entry;
  if not found then
    insert into public.staff_time_entries (user_id) values ((select auth.uid())) returning * into v_entry;
  end if;
  return v_entry;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Gestión del personal

-- Regla de oro: siempre queda al menos un dueño activo.
create function private.keep_an_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.staff where role = 'owner' and status = 'active') then
    raise exception 'Debe quedar al menos un dueño activo' using errcode = '23514';
  end if;
  return null;
end;
$$;
create constraint trigger keep_an_owner after update or delete on public.staff
  deferrable initially immediate
  for each row execute function private.keep_an_owner();

create function private.audit_staff()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform private.audit('staff.create', 'staff', new.user_id::text,
      jsonb_build_object('name', new.full_name, 'role', new.role));
  else
    if new.role is distinct from old.role then
      perform private.audit('staff.role', 'staff', new.user_id::text,
        jsonb_build_object('name', new.full_name, 'from', old.role, 'to', new.role));
    end if;
    if new.status is distinct from old.status then
      perform private.audit('staff.status', 'staff', new.user_id::text,
        jsonb_build_object('name', new.full_name, 'from', old.status, 'to', new.status));
    end if;
  end if;
  return new;
end;
$$;
create trigger audit_staff after insert or update on public.staff
  for each row execute function private.audit_staff();

-- Quién puede tocar a quién: con staff.manage se gestiona al personal, pero
-- solo un dueño crea, edita o asigna dueños.
create function private.assert_can_manage(p_target_role text, p_new_role text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.assert_can('staff.manage');
  if not private.is_backend()
     and (p_target_role = 'owner' or p_new_role = 'owner')
     and private.staff_role() is distinct from 'owner' then
    raise exception 'Solo un dueño puede gestionar a otro dueño' using errcode = '42501';
  end if;
end;
$$;
revoke all on function private.assert_can_manage(text, text) from public, anon, authenticated;

create function public.staff_update(
  p_user_id uuid, p_full_name text, p_role text,
  p_document_id text default null, p_phone text default null, p_email text default null,
  p_hired_on date default null, p_notes text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current text;
begin
  select role into v_current from public.staff where user_id = p_user_id for update;
  if not found then
    raise exception 'La persona no existe' using errcode = 'P0002';
  end if;
  perform private.assert_can_manage(v_current, p_role);

  update public.staff
  set full_name   = trim(p_full_name),
      role        = p_role,
      document_id = nullif(trim(p_document_id), ''),
      phone       = nullif(trim(p_phone), ''),
      email       = nullif(lower(trim(p_email)), ''),
      hired_on    = coalesce(p_hired_on, hired_on),
      notes       = nullif(trim(p_notes), ''),
      updated_at  = now()
  where user_id = p_user_id;
end;
$$;

create function public.staff_set_status(p_user_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current text;
begin
  if p_user_id = (select auth.uid()) then
    raise exception 'No puedes cambiar tu propio estado' using errcode = '42501';
  end if;
  select role into v_current from public.staff where user_id = p_user_id for update;
  if not found then
    raise exception 'La persona no existe' using errcode = 'P0002';
  end if;
  perform private.assert_can_manage(v_current, v_current);

  update public.staff
  set status = p_status,
      terminated_on = case when p_status = 'terminated' then coalesce(terminated_on, current_date) end,
      updated_at = now()
  where user_id = p_user_id;

  -- Quien sale de turno al ser suspendido no se queda con la jornada abierta.
  if p_status <> 'active' then
    update public.staff_time_entries set clock_out = now() where user_id = p_user_id and clock_out is null;
  end if;
end;
$$;

-- Cambiar un permiso de un rol (solo dueños).
create function public.set_role_permission(p_role text, p_permission text, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.assert_can('roles.manage');
  if p_role not in ('admin', 'reception', 'trainer') then
    raise exception 'Rol inválido' using errcode = '22023';
  end if;
  if p_enabled then
    insert into public.role_permissions (role, permission) values (p_role, p_permission) on conflict do nothing;
  else
    delete from public.role_permissions where role = p_role and permission = p_permission;
  end if;
  perform private.audit(case when p_enabled then 'role.grant' else 'role.revoke' end, 'role_permissions', p_role,
    jsonb_build_object('permission', p_permission));
end;
$$;

-- Lo que puede hacer quien llama (la app lo usa para el menú y los botones).
create function public.my_access()
returns table (user_id uuid, full_name text, role text, permissions text[])
language sql
stable
security definer
set search_path = ''
as $$
  select s.user_id, s.full_name, s.role,
         case when s.role = 'owner' then (select array_agg(code order by position) from public.permissions)
              else coalesce((select array_agg(rp.permission order by p.position)
                             from public.role_permissions rp join public.permissions p on p.code = rp.permission
                             where rp.role = s.role), '{}')
         end
  from public.staff s
  where s.user_id = (select auth.uid()) and s.status = 'active';
$$;

-- Directorio del personal con último acceso y si está en turno.
create function public.staff_directory()
returns table (
  user_id uuid, full_name text, role text, status text, document_id text, phone text, email text,
  hired_on date, terminated_on date, notes text, created_at timestamptz,
  last_sign_in_at timestamptz, on_shift_since timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.assert_can('staff.view');
  return query
  select s.user_id, s.full_name, s.role, s.status, s.document_id, s.phone, coalesce(s.email, u.email::text),
         s.hired_on, s.terminated_on, s.notes, s.created_at,
         u.last_sign_in_at,
         (select t.clock_in from public.staff_time_entries t where t.user_id = s.user_id and t.clock_out is null)
  from public.staff s
  left join auth.users u on u.id = s.user_id
  order by (s.status = 'active') desc, s.full_name;
end;
$$;

revoke all on function public.staff_clock() from public, anon;
revoke all on function public.staff_update(uuid, text, text, text, text, text, date, text) from public, anon;
revoke all on function public.staff_set_status(uuid, text) from public, anon;
revoke all on function public.set_role_permission(text, text, boolean) from public, anon;
revoke all on function public.my_access() from public, anon;
revoke all on function public.staff_directory() from public, anon;
grant execute on function public.staff_clock() to authenticated;
grant execute on function public.staff_update(uuid, text, text, text, text, text, date, text) to authenticated;
grant execute on function public.staff_set_status(uuid, text) to authenticated;
grant execute on function public.set_role_permission(text, text, boolean) to authenticated;
grant execute on function public.my_access() to authenticated;
grant execute on function public.staff_directory() to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Vencimiento visible sin acceso a los pagos
--
-- member_overview calculaba el vencimiento leyendo `payments` con los permisos
-- de quien consulta. Un entrenador (sin payments.view) vería a todos "sin
-- plan". La vista pasa a calcularlo con los permisos de su dueño y filtra ella
-- misma: solo devuelve filas a quien tiene members.view. Solo expone la fecha
-- de vencimiento y el nombre del plan, nunca montos.

drop view public.member_overview;
create view public.member_overview
with (security_invoker = false) as
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
where m.deleted_at is null
  and (select private.can('members.view'));

revoke all on public.member_overview from anon, authenticated;
grant select on public.member_overview to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Tiempo real: cambios de rol, permisos y jornadas llegan al instante.

alter publication supabase_realtime add table
  public.staff,
  public.role_permissions,
  public.staff_time_entries;
