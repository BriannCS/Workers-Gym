-- Hecho por Briann$ Workers Corp.
-- Endurecimiento de seguridad (auditoría del 13 oct 2026).
--
-- Hallazgos confirmados con pruebas en producción (en transacción revertida):
-- un usuario del PERSONAL podía saltarse la app usando la API directamente y
--   1. insertar un pago de $0 por un año,
--   2. anular un pago a nombre de otro y "des-anularlo",
--   3. fijar el stock a mano sin compra,
--   4. cobrar en Bs. con una tasa absurda y con fecha de hace 400 días.
--
-- Corrección: el dinero y el stock solo se mueven con funciones del servidor.
-- Son SECURITY DEFINER (las tablas ya no aceptan escritura directa) y por eso
-- cada una verifica primero que quien llama sea personal; viven con
-- search_path vacío y sin permiso de ejecución para public/anon.

-- ---------------------------------------------------------------------------
-- Guardas internas (esquema privado, no expuesto por la API)

create or replace function private.assert_staff()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_staff() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
end;
$$;

-- Tasa razonable: positiva y, si hay cobros en Bs. de los últimos 7 días,
-- entre la mitad y 1,5 veces la tasa más alta usada (frena tasas absurdas sin
-- impedir cambiar de BCV a euro o paralelo).
create or replace function private.assert_valid_rate(p_rate numeric, p_rate_source text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ref numeric;
begin
  if p_rate is null or p_rate <= 0 or p_rate > 1000000 then
    raise exception 'Tasa de cambio inválida' using errcode = '22023';
  end if;
  if p_rate_source is null or p_rate_source not in ('bcv_usd', 'bcv_eur', 'paralelo', 'manual') then
    raise exception 'Fuente de tasa inválida' using errcode = '22023';
  end if;
  select max(rate) into v_ref from (
    select rate from public.payments where rate is not null and voided_at is null and paid_at > now() - interval '7 days'
    union all
    select rate from public.sales where rate is not null and voided_at is null and sold_at > now() - interval '7 days'
  ) recent;
  if v_ref is not null and (p_rate < v_ref * 0.5 or p_rate > v_ref * 1.5) then
    raise exception 'Tasa fuera de rango: % (referencia de los últimos 7 días: %). Revísala en Ajustes.', p_rate, v_ref
      using errcode = '22023';
  end if;
end;
$$;

revoke all on function private.assert_staff() from public, anon, authenticated;
revoke all on function private.assert_valid_rate(numeric, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Cobros de membresía

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

  -- La fecha local de recepción solo puede ser hoy (±1 día por zona horaria).
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

  return v_payment;
end;
$$;

create or replace function public.void_payment(p_payment_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.assert_staff();
  if length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception 'Indica el motivo de la anulación' using errcode = '22023';
  end if;
  update public.payments
  set voided_at = now(), voided_by = (select auth.uid()), void_reason = left(trim(p_reason), 300)
  where id = p_payment_id and voided_at is null;
  if not found then
    raise exception 'El pago no existe o ya estaba anulado' using errcode = 'P0002';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Ventas de tienda

create or replace function public.register_sale(
  p_items jsonb, p_method text, p_member_id uuid default null,
  p_rate numeric default null, p_rate_source text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale_id  uuid;
  v_item     record;
  v_product  public.products;
  v_total    integer := 0;
  v_currency text;
begin
  perform private.assert_staff();

  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no tiene productos' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) > 100 then
    raise exception 'Demasiados productos en una venta' using errcode = '22023';
  end if;

  select currency into v_currency from public.payment_methods where code = p_method and active;
  if not found then
    raise exception 'El método de pago no existe o está desactivado' using errcode = 'P0002';
  end if;
  if v_currency = 'VES' then
    perform private.assert_valid_rate(p_rate, p_rate_source);
  end if;
  if p_member_id is not null and not exists (select 1 from public.members where id = p_member_id) then
    raise exception 'El cliente no existe' using errcode = 'P0002';
  end if;

  insert into public.sales (member_id, method, total_cents, currency, rate, rate_source, total_ves_cents, created_by)
  values (
    p_member_id, p_method, 0, v_currency,
    case when v_currency = 'VES' then p_rate end,
    case when v_currency = 'VES' then p_rate_source end,
    case when v_currency = 'VES' then 0 end,
    (select auth.uid())
  )
  returning id into v_sale_id;

  -- Agrupa por producto y bloquea en orden de id para evitar deadlocks.
  for v_item in
    select (e ->> 'product_id')::uuid as product_id, sum(coalesce((e ->> 'quantity')::integer, 0))::integer as quantity
    from jsonb_array_elements(p_items) e
    group by 1
    order by 1
  loop
    if v_item.quantity <= 0 or v_item.quantity > 10000 then
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

create or replace function public.void_sale(p_sale_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.assert_staff();
  if length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception 'Indica el motivo de la anulación' using errcode = '22023';
  end if;

  update public.sales
  set voided_at = now(), voided_by = (select auth.uid()), void_reason = left(trim(p_reason), 300)
  where id = p_sale_id and voided_at is null;
  if not found then
    raise exception 'La venta no existe o ya estaba anulada' using errcode = 'P0002';
  end if;

  update public.products p
  set stock = p.stock + si.quantity
  from public.sale_items si
  where si.sale_id = p_sale_id and p.id = si.product_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Inventario: stock inicial / ajustes y compras

create or replace function public.add_stock(p_product_id uuid, p_quantity integer, p_unit_cost_cents integer default null, p_note text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stock integer;
begin
  perform private.assert_staff();
  if coalesce(p_quantity, 0) = 0 or abs(p_quantity) > 100000 then
    raise exception 'Cantidad inválida' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_note, ''))) = 0 then
    raise exception 'Indica el motivo del ajuste' using errcode = '22023';
  end if;
  if p_unit_cost_cents is not null and p_unit_cost_cents < 0 then
    raise exception 'Costo inválido' using errcode = '22023';
  end if;

  update public.products
  set stock = stock + p_quantity,
      cost_cents = coalesce(p_unit_cost_cents, cost_cents)
  where id = p_product_id
  returning stock into v_stock;
  if not found then
    raise exception 'El producto no existe' using errcode = 'P0002';
  end if;

  insert into public.stock_entries (product_id, quantity, unit_cost_cents, note, created_by)
  values (p_product_id, p_quantity, p_unit_cost_cents, left(trim(p_note), 300), (select auth.uid()));
  return v_stock;
exception
  when check_violation then
    raise exception 'El ajuste dejaría el stock en negativo' using errcode = 'P0001';
end;
$$;

create or replace function public.register_purchase(
  p_items jsonb, p_supplier_id uuid default null, p_invoice text default null,
  p_purchased_on date default null, p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id    uuid;
  v_item  record;
  v_total integer := 0;
  v_date  date := coalesce(p_purchased_on, current_date);
begin
  perform private.assert_staff();

  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La compra no tiene productos' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) > 200 then
    raise exception 'Demasiadas líneas en una compra' using errcode = '22023';
  end if;
  -- Ni compras futuras ni de hace más de un año.
  if v_date > current_date + 1 or v_date < current_date - 366 then
    raise exception 'Fecha de compra inválida' using errcode = '22023';
  end if;
  if p_supplier_id is not null and not exists (select 1 from public.suppliers where id = p_supplier_id) then
    raise exception 'El proveedor no existe' using errcode = 'P0002';
  end if;

  insert into public.purchases (supplier_id, invoice, purchased_on, notes, created_by)
  values (p_supplier_id, left(nullif(trim(p_invoice), ''), 40), v_date, left(nullif(trim(p_notes), ''), 1000), (select auth.uid()))
  returning id into v_id;

  for v_item in
    select (e ->> 'product_id')::uuid as product_id,
           (e ->> 'quantity')::integer as quantity,
           (e ->> 'unit_cost_cents')::integer as unit_cost_cents
    from jsonb_array_elements(p_items) e
    order by 1
  loop
    if coalesce(v_item.quantity, 0) <= 0 or v_item.quantity > 100000
       or coalesce(v_item.unit_cost_cents, -1) < 0 or v_item.unit_cost_cents > 100000000 then
      raise exception 'Cantidad o costo inválido' using errcode = '22023';
    end if;

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

create or replace function public.void_purchase(p_purchase_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item record;
begin
  perform private.assert_staff();
  if length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception 'Indica el motivo de la anulación' using errcode = '22023';
  end if;

  update public.purchases
  set voided_at = now(), voided_by = (select auth.uid()), void_reason = left(trim(p_reason), 300)
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

-- Solo el personal ejecuta las funciones (además del chequeo interno).
revoke all on function public.register_payment(uuid, uuid, text, date, numeric, text) from public, anon;
revoke all on function public.void_payment(uuid, text) from public, anon;
revoke all on function public.register_sale(jsonb, text, uuid, numeric, text) from public, anon;
revoke all on function public.void_sale(uuid, text) from public, anon;
revoke all on function public.add_stock(uuid, integer, integer, text) from public, anon;
revoke all on function public.register_purchase(jsonb, uuid, text, date, text) from public, anon;
revoke all on function public.void_purchase(uuid, text) from public, anon;
grant execute on function public.register_payment(uuid, uuid, text, date, numeric, text) to authenticated;
grant execute on function public.void_payment(uuid, text) to authenticated;
grant execute on function public.register_sale(jsonb, text, uuid, numeric, text) to authenticated;
grant execute on function public.void_sale(uuid, text) to authenticated;
grant execute on function public.add_stock(uuid, integer, integer, text) to authenticated;
grant execute on function public.register_purchase(jsonb, uuid, text, date, text) to authenticated;
grant execute on function public.void_purchase(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Permisos mínimos: nada de escritura directa sobre dinero, stock ni anulaciones.

revoke insert on public.payments, public.sales, public.sale_items,
  public.purchases, public.purchase_items, public.stock_entries from authenticated;
revoke update (voided_at, voided_by, void_reason) on public.payments from authenticated;
revoke update (total_cents, total_ves_cents, voided_at, voided_by, void_reason) on public.sales from authenticated;
revoke update (total_cents, voided_at, voided_by, void_reason) on public.purchases from authenticated;

-- Productos: se editan datos, nunca el stock (solo compras, ventas y ajustes).
revoke insert, update on public.products from authenticated;
grant insert (name, sku, price_cents, cost_cents, min_stock, supplier_id, active) on public.products to authenticated;
grant update (name, sku, price_cents, cost_cents, min_stock, supplier_id, active) on public.products to authenticated;

-- Asistencia: hora y autor los pone el servidor; no se borra (evidencia).
revoke insert, delete on public.attendance from authenticated;
grant insert (member_id, method) on public.attendance to authenticated;

-- El resto, solo las columnas que la app edita.
revoke insert, update on public.members from authenticated;
grant insert (full_name, document_id, phone, email, notes) on public.members to authenticated;
grant update (full_name, document_id, phone, email, notes, photo_path) on public.members to authenticated;

revoke insert, update on public.plans from authenticated;
grant insert (name, price_cents, duration_days, active) on public.plans to authenticated;
grant update (name, price_cents, duration_days, active) on public.plans to authenticated;

revoke insert, update on public.payment_methods from authenticated;
grant insert (code, name, currency, position) on public.payment_methods to authenticated;
grant update (name, active) on public.payment_methods to authenticated;

revoke update on public.settings from authenticated;
grant update (rate_source, manual_rate, updated_at) on public.settings to authenticated;

revoke insert, update on public.suppliers from authenticated;
grant insert (name, phone, email, notes) on public.suppliers to authenticated;
grant update (name, phone, email, notes) on public.suppliers to authenticated;

-- ---------------------------------------------------------------------------
-- Validación de datos en el servidor (la app ya filtra; esto es defensa en
-- profundidad contra llamadas directas a la API).

alter table public.members
  add constraint members_full_name_len check (char_length(full_name) between 2 and 120),
  add constraint members_document_format check (document_id ~ '^[VE]-[0-9]{6,9}$'),
  add constraint members_phone_format check (phone ~ '^[0-9]{10,11}$'),
  add constraint members_email_format check (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' and char_length(email) <= 120),
  add constraint members_notes_len check (char_length(notes) <= 2000),
  add constraint members_photo_path_format check (photo_path ~ '^[0-9a-f-]{36}/[0-9]+\.(jpg|png|webp)$');

alter table public.suppliers
  add constraint suppliers_name_len check (char_length(name) between 1 and 120),
  add constraint suppliers_phone_format check (phone ~ '^[0-9]{10,11}$'),
  add constraint suppliers_email_format check (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' and char_length(email) <= 120),
  add constraint suppliers_notes_len check (char_length(notes) <= 1000);

alter table public.products
  add constraint products_name_len check (char_length(name) between 1 and 120),
  add constraint products_sku_len check (char_length(sku) <= 40),
  add constraint products_price_max check (price_cents <= 100000000 and cost_cents <= 100000000);

alter table public.plans
  add constraint plans_name_len check (char_length(name) between 1 and 60),
  add constraint plans_limits check (price_cents <= 100000000 and duration_days <= 3660);

alter table public.payment_methods
  add constraint payment_methods_name_len check (char_length(name) between 1 and 40);

alter table public.payments add constraint payments_void_reason_len check (char_length(void_reason) <= 300);
alter table public.sales add constraint sales_void_reason_len check (char_length(void_reason) <= 300);
alter table public.purchases add constraint purchases_void_reason_len check (char_length(void_reason) <= 300);
alter table public.stock_entries add constraint stock_entries_note_len check (char_length(note) <= 300);
