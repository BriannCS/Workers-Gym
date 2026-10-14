-- Hecho por Briann$ Workers Corp.
-- Tienda: proveedores, productos con stock, entradas de mercancía y ventas.
-- El stock solo cambia en funciones transaccionales: una venta que no alcanza
-- se rechaza completa y anular una venta devuelve el stock.

create table public.suppliers (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(trim(name)) > 0),
  phone      text,
  email      text,
  notes      text,
  created_at timestamptz not null default now()
);

create table public.products (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(trim(name)) > 0),
  sku         text unique,
  price_cents integer not null check (price_cents >= 0),
  cost_cents  integer not null default 0 check (cost_cents >= 0),
  stock       integer not null default 0 check (stock >= 0),
  min_stock   integer not null default 0 check (min_stock >= 0),
  supplier_id uuid references public.suppliers (id) on delete set null,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create index products_supplier_id_idx on public.products (supplier_id);

-- Entradas de mercancía y ajustes (quantity negativa = merma/ajuste).
create table public.stock_entries (
  id              uuid primary key default gen_random_uuid(),
  product_id      uuid not null references public.products (id),
  quantity        integer not null check (quantity <> 0),
  unit_cost_cents integer check (unit_cost_cents >= 0),
  note            text,
  created_at      timestamptz not null default now(),
  created_by      uuid default auth.uid()
);
create index stock_entries_product_id_idx on public.stock_entries (product_id, created_at desc);

create table public.sales (
  id          uuid primary key default gen_random_uuid(),
  member_id   uuid references public.members (id),
  method      text not null check (method in ('efectivo', 'transferencia', 'tarjeta', 'otro')),
  total_cents integer not null check (total_cents >= 0),
  sold_at     timestamptz not null default now(),
  created_by  uuid default auth.uid(),
  voided_at   timestamptz,
  voided_by   uuid,
  void_reason text,
  check ((voided_at is null) = (void_reason is null))
);
create index sales_member_id_idx on public.sales (member_id);
create index sales_sold_at_idx on public.sales (sold_at desc);

create table public.sale_items (
  id               uuid primary key default gen_random_uuid(),
  sale_id          uuid not null references public.sales (id) on delete cascade,
  product_id       uuid not null references public.products (id),
  quantity         integer not null check (quantity > 0),
  -- Copias al momento de la venta: el historial no cambia si cambian los precios.
  unit_price_cents integer not null check (unit_price_cents >= 0),
  unit_cost_cents  integer not null check (unit_cost_cents >= 0)
);
create index sale_items_sale_id_idx on public.sale_items (sale_id);
create index sale_items_product_id_idx on public.sale_items (product_id);

-- ---------------------------------------------------------------------------
-- Funciones

-- p_items: [{"product_id": "...", "quantity": 2}, ...]. Precios desde la BD.
create function public.register_sale(p_items jsonb, p_method text, p_member_id uuid default null)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_sale_id uuid;
  v_item    record;
  v_product public.products;
  v_total   integer := 0;
begin
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no tiene productos' using errcode = '22023';
  end if;

  insert into public.sales (member_id, method, total_cents)
  values (p_member_id, p_method, 0)
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

  update public.sales set total_cents = v_total where id = v_sale_id;
  return v_sale_id;
end;
$$;

create function public.void_sale(p_sale_id uuid, p_reason text)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception 'Indica el motivo de la anulación' using errcode = '22023';
  end if;

  update public.sales
  set voided_at = now(), voided_by = (select auth.uid()), void_reason = trim(p_reason)
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

-- Entrada de mercancía (quantity > 0) o ajuste (quantity < 0). Devuelve el nuevo stock.
create function public.add_stock(p_product_id uuid, p_quantity integer, p_unit_cost_cents integer default null, p_note text default null)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_stock integer;
begin
  if coalesce(p_quantity, 0) = 0 then
    raise exception 'La cantidad no puede ser cero' using errcode = '22023';
  end if;

  update public.products
  set stock = stock + p_quantity,
      cost_cents = coalesce(p_unit_cost_cents, cost_cents)
  where id = p_product_id
  returning stock into v_stock;
  if not found then
    raise exception 'El producto no existe' using errcode = 'P0002';
  end if;

  insert into public.stock_entries (product_id, quantity, unit_cost_cents, note)
  values (p_product_id, p_quantity, p_unit_cost_cents, nullif(trim(p_note), ''));
  return v_stock;
exception
  when check_violation then
    raise exception 'El ajuste dejaría el stock en negativo' using errcode = 'P0001';
end;
$$;

-- ---------------------------------------------------------------------------
-- Permisos

revoke all on public.suppliers, public.products, public.stock_entries, public.sales, public.sale_items
  from anon, authenticated;

grant select, insert, update on public.suppliers, public.products to authenticated;
grant select, insert on public.stock_entries, public.sale_items to authenticated;
grant select, insert on public.sales to authenticated;
grant update (total_cents, voided_at, voided_by, void_reason) on public.sales to authenticated;

revoke all on function public.register_sale(jsonb, text, uuid) from public, anon;
revoke all on function public.void_sale(uuid, text) from public, anon;
revoke all on function public.add_stock(uuid, integer, integer, text) from public, anon;
grant execute on function public.register_sale(jsonb, text, uuid) to authenticated;
grant execute on function public.void_sale(uuid, text) to authenticated;
grant execute on function public.add_stock(uuid, integer, integer, text) to authenticated;

alter table public.suppliers     enable row level security;
alter table public.products      enable row level security;
alter table public.stock_entries enable row level security;
alter table public.sales         enable row level security;
alter table public.sale_items    enable row level security;

create policy "staff_only" on public.suppliers
  for all to authenticated using ((select private.is_staff())) with check ((select private.is_staff()));
create policy "staff_only" on public.products
  for all to authenticated using ((select private.is_staff())) with check ((select private.is_staff()));
create policy "staff_only" on public.stock_entries
  for all to authenticated using ((select private.is_staff())) with check ((select private.is_staff()));
create policy "staff_only" on public.sales
  for all to authenticated using ((select private.is_staff())) with check ((select private.is_staff()));
create policy "staff_only" on public.sale_items
  for all to authenticated using ((select private.is_staff())) with check ((select private.is_staff()));
