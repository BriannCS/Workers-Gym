-- Hecho por Briann$ Workers Corp.
-- Métodos de pago configurables, cobro en bolívares con tasa, ajustes
-- compartidos, compras (alimentan el inventario) y fotos de clientes.

-- ---------------------------------------------------------------------------
-- Métodos de pago

create table public.payment_methods (
  code       text primary key check (code ~ '^[a-z0-9_]{2,40}$'),
  name       text not null check (length(trim(name)) > 0),
  currency   text not null check (currency in ('USD', 'VES')),
  active     boolean not null default true,
  position   integer not null default 0,
  created_at timestamptz not null default now()
);

insert into public.payment_methods (code, name, currency, position) values
  ('efectivo_usd', 'Efectivo ($)', 'USD', 1),
  ('efectivo_bs', 'Efectivo (Bs.)', 'VES', 2),
  ('transferencia', 'Transferencia', 'VES', 3),
  ('pago_movil', 'Pago móvil', 'VES', 4),
  ('binance', 'Binance', 'USD', 5),
  ('zelle', 'Zelle', 'USD', 6);

-- Conserva cualquier método antiguo ya usado ('efectivo', 'tarjeta', 'otro')
-- como inactivo, para que el historial siga siendo válido.
insert into public.payment_methods (code, name, currency, active, position)
select distinct m.method, initcap(m.method), 'USD', false, 99
from (select method from public.payments union select method from public.sales) m
where m.method not in (select code from public.payment_methods);

alter table public.payments drop constraint if exists payments_method_check;
alter table public.sales drop constraint if exists sales_method_check;
alter table public.payments
  add constraint payments_method_fkey foreign key (method) references public.payment_methods (code) on update cascade;
alter table public.sales
  add constraint sales_method_fkey foreign key (method) references public.payment_methods (code) on update cascade;
create index payments_method_idx on public.payments (method);
create index sales_method_idx on public.sales (method);

-- ---------------------------------------------------------------------------
-- Moneda y tasa de cada cobro. Los precios siguen en USD (centavos); si el
-- método es en bolívares se guarda la tasa usada y el monto en Bs.

alter table public.payments
  add column currency text not null default 'USD' check (currency in ('USD', 'VES')),
  add column rate numeric(18, 6) check (rate > 0),
  add column rate_source text check (rate_source in ('bcv_usd', 'bcv_eur', 'paralelo', 'manual')),
  add column amount_ves_cents bigint check (amount_ves_cents >= 0),
  add constraint payments_ves_has_rate check (currency = 'USD' or (rate is not null and amount_ves_cents is not null));

alter table public.sales
  add column currency text not null default 'USD' check (currency in ('USD', 'VES')),
  add column rate numeric(18, 6) check (rate > 0),
  add column rate_source text check (rate_source in ('bcv_usd', 'bcv_eur', 'paralelo', 'manual')),
  add column total_ves_cents bigint check (total_ves_cents >= 0),
  add constraint sales_ves_has_rate check (currency = 'USD' or (rate is not null and total_ves_cents is not null));

-- ---------------------------------------------------------------------------
-- Ajustes compartidos entre dispositivos (una sola fila)

create table public.settings (
  id          boolean primary key default true check (id),
  rate_source text not null default 'bcv_usd' check (rate_source in ('bcv_usd', 'bcv_eur', 'paralelo', 'manual')),
  manual_rate numeric(18, 6) check (manual_rate > 0),
  updated_at  timestamptz not null default now()
);
insert into public.settings default values;

-- ---------------------------------------------------------------------------
-- Cobros con moneda/tasa (reemplazan las versiones anteriores)

drop function if exists public.register_payment(uuid, uuid, text, date);

create function public.register_payment(
  p_member_id uuid, p_plan_id uuid, p_method text, p_today date,
  p_rate numeric default null, p_rate_source text default null
)
returns public.payments
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_plan     public.plans;
  v_currency text;
  v_last     date;
  v_start    date;
  v_payment  public.payments;
begin
  select * into v_plan from public.plans where id = p_plan_id and active;
  if not found then
    raise exception 'El plan no existe o está archivado' using errcode = 'P0002';
  end if;

  select currency into v_currency from public.payment_methods where code = p_method and active;
  if not found then
    raise exception 'El método de pago no existe o está desactivado' using errcode = 'P0002';
  end if;
  if v_currency = 'VES' and coalesce(p_rate, 0) <= 0 then
    raise exception 'Falta la tasa de cambio para cobrar en bolívares' using errcode = '22023';
  end if;

  -- Bloquea al cliente para que dos cobros simultáneos no calculen el mismo periodo.
  perform 1 from public.members where id = p_member_id for update;
  if not found then
    raise exception 'El cliente no existe' using errcode = 'P0002';
  end if;

  select max(period_end) into v_last
  from public.payments
  where member_id = p_member_id and voided_at is null;

  v_start := case when v_last is not null and v_last >= p_today then v_last + 1 else p_today end;

  insert into public.payments (
    member_id, plan_id, amount_cents, method, period_start, period_end,
    currency, rate, rate_source, amount_ves_cents
  )
  values (
    p_member_id, p_plan_id, v_plan.price_cents, p_method, v_start, v_start + v_plan.duration_days - 1,
    v_currency,
    case when v_currency = 'VES' then p_rate end,
    case when v_currency = 'VES' then p_rate_source end,
    case when v_currency = 'VES' then round(v_plan.price_cents * p_rate) end
  )
  returning * into v_payment;

  return v_payment;
end;
$$;

drop function if exists public.register_sale(jsonb, text, uuid);

create function public.register_sale(
  p_items jsonb, p_method text, p_member_id uuid default null,
  p_rate numeric default null, p_rate_source text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_sale_id  uuid;
  v_item     record;
  v_product  public.products;
  v_total    integer := 0;
  v_currency text;
begin
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no tiene productos' using errcode = '22023';
  end if;

  select currency into v_currency from public.payment_methods where code = p_method and active;
  if not found then
    raise exception 'El método de pago no existe o está desactivado' using errcode = 'P0002';
  end if;
  if v_currency = 'VES' and coalesce(p_rate, 0) <= 0 then
    raise exception 'Falta la tasa de cambio para cobrar en bolívares' using errcode = '22023';
  end if;

  insert into public.sales (member_id, method, total_cents, currency, rate, rate_source)
  values (
    p_member_id, p_method, 0, v_currency,
    case when v_currency = 'VES' then p_rate end,
    case when v_currency = 'VES' then p_rate_source end
  )
  returning id into v_sale_id;

  -- Agrupa por producto y bloquea en orden de id para evitar deadlocks.
  for v_item in
    select (e ->> 'product_id')::uuid as product_id, sum(coalesce((e ->> 'quantity')::integer, 0))::integer as quantity
    from jsonb_array_elements(p_items) e
    group by 1
    order by 1
  loop
    if v_item.quantity <= 0 then
      raise exception 'Cantidad inválida' using errcode = '22023';
    end if;

    update public.products
    set stock = stock - v_item.quantity
    where id = v_item.product_id and active and stock >= v_item.quantity
    returning * into v_product;

    if not found then
      select * into v_product from public.products where id = v_item.product_id;
      raise exception 'Stock insuficiente de % (quedan %)', coalesce(v_product.name, 'producto'), coalesce(v_product.stock, 0)
        using errcode = 'P0001';
    end if;

    insert into public.sale_items (sale_id, product_id, quantity, unit_price_cents, unit_cost_cents)
    values (v_sale_id, v_item.product_id, v_item.quantity, v_product.price_cents, v_product.cost_cents);
    v_total := v_total + v_item.quantity * v_product.price_cents;
  end loop;

  update public.sales
  set total_cents = v_total,
      total_ves_cents = case when v_currency = 'VES' then round(v_total * p_rate) end
  where id = v_sale_id;
  return v_sale_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Compras: alimentan el inventario.
-- stock = stock inicial ± ajustes (stock_entries) + compras − ventas
-- (sin contar anuladas). products.stock es ese valor ya calculado, mantenido
-- en la misma transacción que cada compra/venta/anulación.

create table public.purchases (
  id           uuid primary key default gen_random_uuid(),
  supplier_id  uuid references public.suppliers (id),
  invoice      text,
  purchased_on date not null default current_date,
  notes        text,
  total_cents  integer not null default 0 check (total_cents >= 0),
  created_at   timestamptz not null default now(),
  created_by   uuid default auth.uid(),
  voided_at    timestamptz,
  voided_by    uuid,
  void_reason  text,
  check ((voided_at is null) = (void_reason is null))
);
create index purchases_supplier_id_idx on public.purchases (supplier_id);
create index purchases_purchased_on_idx on public.purchases (purchased_on desc);

create table public.purchase_items (
  id              uuid primary key default gen_random_uuid(),
  purchase_id     uuid not null references public.purchases (id) on delete cascade,
  product_id      uuid not null references public.products (id),
  quantity        integer not null check (quantity > 0),
  unit_cost_cents integer not null check (unit_cost_cents >= 0)
);
create index purchase_items_purchase_id_idx on public.purchase_items (purchase_id);
create index purchase_items_product_id_idx on public.purchase_items (product_id);

-- p_items: [{"product_id": "...", "quantity": 12, "unit_cost_cents": 45}, ...]
create function public.register_purchase(
  p_items jsonb, p_supplier_id uuid default null, p_invoice text default null,
  p_purchased_on date default null, p_notes text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id    uuid;
  v_item  record;
  v_total integer := 0;
begin
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La compra no tiene productos' using errcode = '22023';
  end if;

  insert into public.purchases (supplier_id, invoice, purchased_on, notes)
  values (p_supplier_id, nullif(trim(p_invoice), ''), coalesce(p_purchased_on, current_date), nullif(trim(p_notes), ''))
  returning id into v_id;

  for v_item in
    select (e ->> 'product_id')::uuid as product_id,
           (e ->> 'quantity')::integer as quantity,
           (e ->> 'unit_cost_cents')::integer as unit_cost_cents
    from jsonb_array_elements(p_items) e
    order by 1
  loop
    if coalesce(v_item.quantity, 0) <= 0 or coalesce(v_item.unit_cost_cents, -1) < 0 then
      raise exception 'Cantidad o costo inválido' using errcode = '22023';
    end if;

    -- El costo de referencia del producto pasa a ser el de la última compra.
    update public.products
    set stock = stock + v_item.quantity, cost_cents = v_item.unit_cost_cents
    where id = v_item.product_id;
    if not found then
      raise exception 'El producto no existe' using errcode = 'P0002';
    end if;

    insert into public.purchase_items (purchase_id, product_id, quantity, unit_cost_cents)
    values (v_id, v_item.product_id, v_item.quantity, v_item.unit_cost_cents);
    v_total := v_total + v_item.quantity * v_item.unit_cost_cents;
  end loop;

  update public.purchases set total_cents = v_total where id = v_id;
  return v_id;
end;
$$;

-- Anular una compra retira del stock lo que entró. Si ya se vendió parte, no
-- se puede (el stock quedaría negativo) y no se anula nada.
create function public.void_purchase(p_purchase_id uuid, p_reason text)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_item record;
begin
  if length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception 'Indica el motivo de la anulación' using errcode = '22023';
  end if;

  update public.purchases
  set voided_at = now(), voided_by = (select auth.uid()), void_reason = trim(p_reason)
  where id = p_purchase_id and voided_at is null;
  if not found then
    raise exception 'La compra no existe o ya estaba anulada' using errcode = 'P0002';
  end if;

  for v_item in
    select pi.product_id, sum(pi.quantity)::integer as quantity, p.name, p.stock
    from public.purchase_items pi
    join public.products p on p.id = pi.product_id
    where pi.purchase_id = p_purchase_id
    group by pi.product_id, p.name, p.stock
    order by pi.product_id
  loop
    update public.products set stock = stock - v_item.quantity
    where id = v_item.product_id and stock >= v_item.quantity;
    if not found then
      raise exception 'No se puede anular: ya se vendieron unidades de % (quedan %)', v_item.name, v_item.stock
        using errcode = 'P0001';
    end if;
  end loop;
end;
$$;

-- Auditoría: el stock guardado debe coincidir con el calculado.
create view public.product_stock_audit
with (security_invoker = true) as
select
  p.id,
  p.name,
  p.stock,
  coalesce(adj.qty, 0) + coalesce(buy.qty, 0) - coalesce(sold.qty, 0) as computed_stock
from public.products p
left join (
  select product_id, sum(quantity) as qty from public.stock_entries group by product_id
) adj on adj.product_id = p.id
left join (
  select pi.product_id, sum(pi.quantity) as qty
  from public.purchase_items pi join public.purchases pu on pu.id = pi.purchase_id
  where pu.voided_at is null group by pi.product_id
) buy on buy.product_id = p.id
left join (
  select si.product_id, sum(si.quantity) as qty
  from public.sale_items si join public.sales s on s.id = si.sale_id
  where s.voided_at is null group by si.product_id
) sold on sold.product_id = p.id;

-- ---------------------------------------------------------------------------
-- Fotos de clientes (Storage privado, solo personal)

alter table public.members add column photo_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('member-photos', 'member-photos', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- Subir con upsert requiere INSERT + SELECT + UPDATE.
create policy "staff_read_member_photos" on storage.objects
  for select to authenticated using (bucket_id = 'member-photos' and (select private.is_staff()));
create policy "staff_insert_member_photos" on storage.objects
  for insert to authenticated with check (bucket_id = 'member-photos' and (select private.is_staff()));
create policy "staff_update_member_photos" on storage.objects
  for update to authenticated
  using (bucket_id = 'member-photos' and (select private.is_staff()))
  with check (bucket_id = 'member-photos' and (select private.is_staff()));
create policy "staff_delete_member_photos" on storage.objects
  for delete to authenticated using (bucket_id = 'member-photos' and (select private.is_staff()));

-- ---------------------------------------------------------------------------
-- Permisos

revoke all on public.payment_methods, public.settings, public.purchases, public.purchase_items, public.product_stock_audit
  from anon, authenticated;

grant select, insert, update on public.payment_methods to authenticated;
grant select, update on public.settings to authenticated;
grant select, insert on public.purchases, public.purchase_items to authenticated;
grant update (total_cents, voided_at, voided_by, void_reason) on public.purchases to authenticated;
grant select on public.product_stock_audit to authenticated;
-- La venta ahora también fija el total en Bs.
grant update (total_ves_cents) on public.sales to authenticated;

revoke all on function public.register_payment(uuid, uuid, text, date, numeric, text) from public, anon;
revoke all on function public.register_sale(jsonb, text, uuid, numeric, text) from public, anon;
revoke all on function public.register_purchase(jsonb, uuid, text, date, text) from public, anon;
revoke all on function public.void_purchase(uuid, text) from public, anon;
grant execute on function public.register_payment(uuid, uuid, text, date, numeric, text) to authenticated;
grant execute on function public.register_sale(jsonb, text, uuid, numeric, text) to authenticated;
grant execute on function public.register_purchase(jsonb, uuid, text, date, text) to authenticated;
grant execute on function public.void_purchase(uuid, text) to authenticated;

alter table public.payment_methods enable row level security;
alter table public.settings        enable row level security;
alter table public.purchases       enable row level security;
alter table public.purchase_items  enable row level security;

create policy "staff_only" on public.payment_methods
  for all to authenticated using ((select private.is_staff())) with check ((select private.is_staff()));
create policy "staff_only" on public.settings
  for all to authenticated using ((select private.is_staff())) with check ((select private.is_staff()));
create policy "staff_only" on public.purchases
  for all to authenticated using ((select private.is_staff())) with check ((select private.is_staff()));
create policy "staff_only" on public.purchase_items
  for all to authenticated using ((select private.is_staff())) with check ((select private.is_staff()));

-- Sincronización en tiempo real de lo nuevo.
alter publication supabase_realtime add table public.payment_methods, public.settings, public.purchases;
