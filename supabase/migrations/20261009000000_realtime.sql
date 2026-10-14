-- Hecho por Briann$ Workers Corp.
-- Sincronización en tiempo real entre la PWA y el teléfono.
-- Postgres Changes autoriza cada evento contra las políticas RLS del
-- suscriptor, así que solo el personal (private.is_staff) recibe cambios.
-- Nota: RLS no se aplica a eventos DELETE; sin replica identity full el evento
-- solo trae la clave primaria, que no expone datos del cliente.

alter publication supabase_realtime add table
  public.members,
  public.plans,
  public.payments,
  public.attendance,
  public.suppliers,
  public.products,
  public.sales;
