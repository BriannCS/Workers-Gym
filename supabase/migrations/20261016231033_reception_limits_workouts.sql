-- Hecho por Briann$ - Workers Corp.
--
-- 1. Recepción deja de ver dinero que no le toca: ingresos y totales, su caja,
--    compras y costos. Solo ve el stock actual.
-- 2. Los costos de productos y ventas quedan fuera de la API: se leen con
--    product_costs() y solo con el permiso inventory.cost.
-- 3. Entrenos: los entrenadores anotan qué trabajó cada cliente.

-- ---------------------------------------------------------------------------
-- 1. Permisos nuevos y reparto por rol

update public.permissions set label = 'Ver ingresos y totales (Inicio y Pagos)' where code = 'dashboard.money';
update public.permissions set label = 'Ver productos y stock actual' where code = 'inventory.view';

insert into public.permissions (code, label, module, position) values
  ('workouts.view',  'Ver los entrenos de los clientes',            'Entrenos',   35),
  ('workouts.edit',  'Registrar y editar entrenos',                 'Entrenos',   36),
  ('inventory.cost', 'Ver costos, márgenes y valor del inventario', 'Inventario', 62),
  ('purchases.view', 'Ver compras y proveedores',                   'Compras',    65);

insert into public.role_permissions (role, permission) values
  ('admin',   'workouts.view'),
  ('admin',   'workouts.edit'),
  ('admin',   'inventory.cost'),
  ('admin',   'purchases.view'),
  ('trainer', 'workouts.view'),
  ('trainer', 'workouts.edit');

delete from public.role_permissions
where role = 'reception' and permission in ('dashboard.money', 'cash.own');

-- ---------------------------------------------------------------------------
-- 2. Compras y costos

drop policy "purchases_read" on public.purchases;
create policy "purchases_read" on public.purchases
  for select to authenticated using ((select private.can('purchases.view')));
drop policy "purchase_items_read" on public.purchase_items;
create policy "purchase_items_read" on public.purchase_items
  for select to authenticated using ((select private.can('purchases.view')));
drop policy "stock_entries_read" on public.stock_entries;
create policy "stock_entries_read" on public.stock_entries
  for select to authenticated using ((select private.can('inventory.cost')));

-- El costo ya no se puede leer directo (ni con select=*).
revoke select on public.products from authenticated;
grant select (id, name, sku, price_cents, stock, min_stock, supplier_id, active, created_at)
  on public.products to authenticated;
revoke select on public.sale_items from authenticated;
grant select (id, sale_id, product_id, quantity, unit_price_cents)
  on public.sale_items to authenticated;

create function public.product_costs()
returns table (product_id uuid, cost_cents integer)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.cost_cents from public.products p where private.can('inventory.cost');
$$;
revoke all on function public.product_costs() from public, anon;
grant execute on function public.product_costs() to authenticated;

-- Cambiar el costo también exige inventory.manage (antes se colaba).
create or replace function private.guard_products()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT'
     or (new.name, new.sku, new.price_cents, new.cost_cents, new.min_stock, new.supplier_id, new.active)
        is distinct from (old.name, old.sku, old.price_cents, old.cost_cents, old.min_stock, old.supplier_id, old.active) then
    perform private.assert_can('inventory.manage');
  end if;
  if tg_op = 'UPDATE' and new.price_cents is distinct from old.price_cents then
    perform private.audit('product.price', 'products', new.id::text,
      jsonb_build_object('name', new.name, 'from', old.price_cents, 'to', new.price_cents));
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Entrenos

create table public.workout_logs (
  id            uuid primary key default gen_random_uuid(),
  member_id     uuid not null references public.members (id) on delete cascade,
  trained_on    date not null default current_date,
  body_parts    text[] not null default '{}',
  workout_types text[] not null default '{}',
  duration_min  integer check (duration_min between 1 and 600),
  effort        smallint check (effort between 1 and 5),
  notes         text check (char_length(notes) <= 2000),
  created_by    uuid not null default auth.uid(),
  trainer_name  text not null default '',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint workout_logs_parts check (body_parts <@ array[
    'pecho', 'espalda', 'hombros', 'biceps', 'triceps', 'antebrazos', 'abdomen', 'lumbar',
    'gluteos', 'cuadriceps', 'isquios', 'aductores', 'pantorrillas', 'cuerpo_completo']::text[]),
  constraint workout_logs_types check (workout_types <@ array[
    'fuerza', 'hipertrofia', 'resistencia', 'cardio', 'hiit', 'funcional', 'movilidad',
    'tecnica', 'rehabilitacion', 'evaluacion']::text[]),
  constraint workout_logs_content check (
    cardinality(body_parts) + cardinality(workout_types) > 0 or coalesce(btrim(notes), '') <> ''),
  constraint workout_logs_date check (trained_on between date '2020-01-01' and current_date + 1)
);
create index workout_logs_member_idx on public.workout_logs (member_id, trained_on desc);
create index workout_logs_day_idx on public.workout_logs (trained_on desc, created_at desc);

-- Quién lo anotó lo pone el servidor; solo se edita lo propio, salvo dueño y
-- administrador.
create function private.guard_workout_logs()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.assert_can('workouts.edit');
  if tg_op = 'INSERT' then
    if not private.is_backend() then
      new.created_by := (select auth.uid());
    end if;
    new.trainer_name := coalesce((select s.full_name from public.staff s where s.user_id = new.created_by), '');
    new.created_at := now();
  else
    if old.created_by is distinct from (select auth.uid())
       and not private.is_backend()
       and coalesce(private.staff_role(), '') not in ('owner', 'admin') then
      raise exception 'Solo puedes editar los entrenos que registraste tú' using errcode = '42501';
    end if;
    new.created_by := old.created_by;
    new.trainer_name := old.trainer_name;
    new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  return new;
end;
$$;
create trigger guard_workout_logs before insert or update on public.workout_logs
  for each row execute function private.guard_workout_logs();

alter table public.workout_logs enable row level security;
create policy "workout_logs_read" on public.workout_logs
  for select to authenticated using ((select private.can('workouts.view')));
create policy "workout_logs_insert" on public.workout_logs
  for insert to authenticated with check ((select private.can('workouts.edit')));
create policy "workout_logs_update" on public.workout_logs
  for update to authenticated using ((select private.can('workouts.edit')));
create policy "workout_logs_delete" on public.workout_logs
  for delete to authenticated using (
    (select private.can('workouts.edit'))
    and (created_by = (select auth.uid()) or (select private.staff_role()) in ('owner', 'admin')));

revoke all on public.workout_logs from anon, authenticated;
grant select, delete on public.workout_logs to authenticated;
grant insert (member_id, trained_on, body_parts, workout_types, duration_min, effort, notes)
  on public.workout_logs to authenticated;
grant update (member_id, trained_on, body_parts, workout_types, duration_min, effort, notes)
  on public.workout_logs to authenticated;

alter publication supabase_realtime add table public.workout_logs;
