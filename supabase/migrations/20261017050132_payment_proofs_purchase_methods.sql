-- Hecho por Briann$ - Workers Corp.
--
-- Pendientes de pagos, compras e inventario (docs/pendientes.md):
-- 1. Pago móvil (y otros métodos con referencia) con datos del pagador,
--    foto del comprobante y verificación contra el banco, en cobros de
--    membresía y en ventas de la tienda.
-- 2. Método de pago y moneda en cada compra a proveedores (Bs. con tasa).
-- Crear productos desde la compra y escanear el código no necesitan cambios
-- en la base: usan saveProduct y el campo sku que ya existen.

-- ---------------------------------------------------------------------------
-- 1. Métodos que piden referencia

alter table public.payment_methods
  add column requires_reference boolean not null default false;

update public.payment_methods set requires_reference = true
where code in ('pago_movil', 'transferencia', 'zelle', 'binance');

-- ---------------------------------------------------------------------------
-- 2. Datos del comprobante en cobros y ventas

alter table public.payments
  add column reference    text check (char_length(reference) between 3 and 40),
  add column payer_bank   text check (char_length(payer_bank) <= 60),
  add column payer_id     text check (char_length(payer_id) <= 30),
  add column receipt_path text check (char_length(receipt_path) <= 200),
  add column verified_at  timestamptz,
  add column verified_by  uuid references auth.users (id);

alter table public.sales
  add column reference    text check (char_length(reference) between 3 and 40),
  add column payer_bank   text check (char_length(payer_bank) <= 60),
  add column payer_id     text check (char_length(payer_id) <= 30),
  add column receipt_path text check (char_length(receipt_path) <= 200),
  add column verified_at  timestamptz,
  add column verified_by  uuid references auth.users (id);

-- La misma referencia del mismo banco no se cobra dos veces (sin contar
-- anulados). La comprobación entre cobros y ventas la hace la función.
create unique index payments_reference_uniq on public.payments (method, coalesce(payer_bank, ''), lower(reference))
  where reference is not null and voided_at is null;
create unique index sales_reference_uniq on public.sales (method, coalesce(payer_bank, ''), lower(reference))
  where reference is not null and voided_at is null;

create function private.clean_proof(p_method text, p_reference text, p_payer_bank text, p_payer_id text)
returns table (reference text, payer_bank text, payer_id text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ref  text := nullif(regexp_replace(trim(coalesce(p_reference, '')), '\s+', '', 'g'), '');
  v_bank text := nullif(trim(coalesce(p_payer_bank, '')), '');
  v_id   text := nullif(trim(coalesce(p_payer_id, '')), '');
  v_needs boolean;
begin
  select requires_reference into v_needs from public.payment_methods where code = p_method;
  if coalesce(v_needs, false) and v_ref is null then
    raise exception 'Este método de pago necesita el número de referencia' using errcode = '22023';
  end if;
  if v_ref is not null and char_length(v_ref) not between 3 and 40 then
    raise exception 'La referencia debe tener entre 3 y 40 caracteres' using errcode = '22023';
  end if;
  if v_ref is not null and (
    exists (select 1 from public.payments p where p.method = p_method and coalesce(p.payer_bank, '') = coalesce(v_bank, '')
            and lower(p.reference) = lower(v_ref) and p.voided_at is null)
    or exists (select 1 from public.sales s where s.method = p_method and coalesce(s.payer_bank, '') = coalesce(v_bank, '')
            and lower(s.reference) = lower(v_ref) and s.voided_at is null)
  ) then
    raise exception 'La referencia % ya está registrada en otro pago', v_ref using errcode = '23505';
  end if;
  return query select v_ref, left(v_bank, 60), left(v_id, 30);
end;
$$;
revoke all on function private.clean_proof(text, text, text, text) from public, anon, authenticated;

-- Cobro de membresía: mismos pasos de antes + comprobante.
drop function public.register_payment(uuid, uuid, text, date, numeric, text);
create function public.register_payment(
  p_member_id uuid, p_plan_id uuid, p_method text, p_today date,
  p_rate numeric default null, p_rate_source text default null,
  p_reference text default null, p_payer_bank text default null, p_payer_id text default null)
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
  v_proof    record;
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
  select * into v_proof from private.clean_proof(p_method, p_reference, p_payer_bank, p_payer_id);

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
    currency, rate, rate_source, amount_ves_cents, created_by,
    reference, payer_bank, payer_id
  )
  values (
    p_member_id, p_plan_id, v_plan.price_cents, p_method, v_start, v_start + v_plan.duration_days - 1,
    v_currency,
    case when v_currency = 'VES' then p_rate end,
    case when v_currency = 'VES' then p_rate_source end,
    case when v_currency = 'VES' then round(v_plan.price_cents * p_rate) end,
    (select auth.uid()),
    v_proof.reference, v_proof.payer_bank, v_proof.payer_id
  )
  returning * into v_payment;

  update public.members set active = true where id = p_member_id and not active;

  return v_payment;
end;
$$;
revoke all on function public.register_payment(uuid, uuid, text, date, numeric, text, text, text, text) from public, anon;
grant execute on function public.register_payment(uuid, uuid, text, date, numeric, text, text, text, text) to authenticated;

-- Venta de la tienda: mismos pasos de antes + comprobante.
drop function public.register_sale(jsonb, text, uuid, numeric, text);
create function public.register_sale(
  p_items jsonb, p_method text, p_member_id uuid default null,
  p_rate numeric default null, p_rate_source text default null,
  p_reference text default null, p_payer_bank text default null, p_payer_id text default null)
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
  v_proof    record;
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
  select * into v_proof from private.clean_proof(p_method, p_reference, p_payer_bank, p_payer_id);

  insert into public.sales (member_id, method, total_cents, currency, rate, rate_source, total_ves_cents, created_by,
                            reference, payer_bank, payer_id)
  values (
    p_member_id, p_method, 0, v_currency,
    case when v_currency = 'VES' then p_rate end,
    case when v_currency = 'VES' then p_rate_source end,
    case when v_currency = 'VES' then 0 end,
    (select auth.uid()),
    v_proof.reference, v_proof.payer_bank, v_proof.payer_id
  )
  returning id into v_sale_id;

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
revoke all on function public.register_sale(jsonb, text, uuid, numeric, text, text, text, text) from public, anon;
grant execute on function public.register_sale(jsonb, text, uuid, numeric, text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Verificación contra el banco

insert into public.permissions (code, label, module, position) values
  ('payments.verify', 'Verificar pagos contra el banco', 'Pagos', 43);
insert into public.role_permissions (role, permission) values ('admin', 'payments.verify');

-- p_kind: 'payment' (membresía) o 'sale' (tienda).
create function public.set_payment_verified(p_kind text, p_id uuid, p_verified boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.assert_can('payments.verify');
  if p_kind = 'payment' then
    update public.payments
    set verified_at = case when p_verified then now() end,
        verified_by = case when p_verified then (select auth.uid()) end
    where id = p_id and voided_at is null;
  elsif p_kind = 'sale' then
    update public.sales
    set verified_at = case when p_verified then now() end,
        verified_by = case when p_verified then (select auth.uid()) end
    where id = p_id and voided_at is null;
  else
    raise exception 'Tipo inválido' using errcode = '22023';
  end if;
  if not found then
    raise exception 'El pago no existe o está anulado' using errcode = 'P0002';
  end if;
  perform private.audit(case when p_verified then 'payment.verify' else 'payment.unverify' end,
    case when p_kind = 'payment' then 'payments' else 'sales' end, p_id::text, '{}'::jsonb);
end;
$$;
revoke all on function public.set_payment_verified(text, uuid, boolean) from public, anon;
grant execute on function public.set_payment_verified(text, uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Fotos de comprobantes: bucket privado, carpetas payments/<id>/ y sales/<id>/

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('payment-receipts', 'payment-receipts', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']);

create policy "receipts_read" on storage.objects
  for select to authenticated using (
    bucket_id = 'payment-receipts' and (
      (name like 'payments/%' and (select private.can('payments.view')))
      or (name like 'sales/%' and ((select private.can('store.sell')) or (select private.can('cash.all'))))));

create policy "receipts_insert" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'payment-receipts' and (
      (name like 'payments/%' and (select private.can('payments.create')))
      or (name like 'sales/%' and (select private.can('store.sell')))));

-- Asocia la foto subida al cobro o venta. Quien lo registró puede cambiarla;
-- los demás solo si aún no tiene, salvo quien verifica pagos.
create function public.attach_receipt(p_kind text, p_id uuid, p_path text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_folder text;
  v_owner  uuid;
  v_path   text;
begin
  if p_kind = 'payment' then
    perform private.assert_can('payments.create');
    v_folder := 'payments/';
    select created_by, receipt_path into v_owner, v_path from public.payments where id = p_id and voided_at is null;
  elsif p_kind = 'sale' then
    perform private.assert_can('store.sell');
    v_folder := 'sales/';
    select created_by, receipt_path into v_owner, v_path from public.sales where id = p_id and voided_at is null;
  else
    raise exception 'Tipo inválido' using errcode = '22023';
  end if;
  if not found then
    raise exception 'El pago no existe o está anulado' using errcode = 'P0002';
  end if;
  if p_path is null or p_path not like v_folder || p_id::text || '/%' or char_length(p_path) > 200 then
    raise exception 'Ruta de comprobante inválida' using errcode = '22023';
  end if;
  if v_path is not null and v_owner is distinct from (select auth.uid()) and not private.can('payments.verify') then
    raise exception 'Este pago ya tiene comprobante; solo quien lo cobró o un verificador puede cambiarlo' using errcode = '42501';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'payment-receipts' and o.name = p_path) then
    raise exception 'La foto del comprobante no se subió' using errcode = 'P0002';
  end if;

  if p_kind = 'payment' then
    update public.payments set receipt_path = p_path where id = p_id;
  else
    update public.sales set receipt_path = p_path where id = p_id;
  end if;
  perform private.audit('payment.receipt', case when p_kind = 'payment' then 'payments' else 'sales' end, p_id::text,
    jsonb_build_object('path', p_path, 'replaced', v_path is not null));
end;
$$;
revoke all on function public.attach_receipt(text, uuid, text) from public, anon;
grant execute on function public.attach_receipt(text, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Compras: método de pago y moneda

alter table public.purchases
  add column method            text references public.payment_methods (code) on update cascade,
  add column currency          text not null default 'USD' check (currency in ('USD', 'VES')),
  add column rate              numeric check (rate > 0),
  add column rate_source       text check (rate_source in ('bcv_usd', 'bcv_eur', 'paralelo', 'manual')),
  add column total_ves_cents   bigint check (total_ves_cents >= 0),
  add column payment_reference text check (char_length(payment_reference) <= 40),
  add constraint purchases_ves_has_rate check (currency = 'USD' or (rate is not null and total_ves_cents is not null));

drop function public.register_purchase(jsonb, uuid, text, date, text);
create function public.register_purchase(
  p_items jsonb, p_supplier_id uuid default null, p_invoice text default null,
  p_purchased_on date default null, p_notes text default null,
  p_method text default null, p_rate numeric default null, p_rate_source text default null,
  p_payment_reference text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id       uuid;
  v_item     record;
  v_total    integer := 0;
  v_date     date := coalesce(p_purchased_on, current_date);
  v_currency text := 'USD';
begin
  perform private.assert_staff();

  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La compra no tiene productos' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) > 200 then
    raise exception 'Demasiadas líneas en una compra' using errcode = '22023';
  end if;
  if v_date > current_date + 1 or v_date < current_date - 366 then
    raise exception 'Fecha de compra inválida' using errcode = '22023';
  end if;
  if p_supplier_id is not null and not exists (select 1 from public.suppliers where id = p_supplier_id) then
    raise exception 'El proveedor no existe' using errcode = 'P0002';
  end if;
  if p_method is not null then
    select currency into v_currency from public.payment_methods where code = p_method;
    if not found then
      raise exception 'El método de pago no existe' using errcode = 'P0002';
    end if;
    if v_currency = 'VES' then
      perform private.assert_valid_rate(p_rate, p_rate_source);
    end if;
  end if;

  insert into public.purchases (supplier_id, invoice, purchased_on, notes, created_by,
                                method, currency, rate, rate_source, total_ves_cents, payment_reference)
  values (p_supplier_id, left(nullif(trim(p_invoice), ''), 40), v_date, left(nullif(trim(p_notes), ''), 1000), (select auth.uid()),
          p_method, v_currency,
          case when v_currency = 'VES' then p_rate end,
          case when v_currency = 'VES' then p_rate_source end,
          case when v_currency = 'VES' then 0 end,
          left(nullif(trim(p_payment_reference), ''), 40))
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

  update public.purchases
  set total_cents = v_total,
      total_ves_cents = case when v_currency = 'VES' then round(v_total * p_rate) end
  where id = v_id;
  return v_id;
end;
$$;
revoke all on function public.register_purchase(jsonb, uuid, text, date, text, text, numeric, text, text) from public, anon;
grant execute on function public.register_purchase(jsonb, uuid, text, date, text, text, numeric, text, text) to authenticated;
