// Hecho por Briann$ - Workers Corp.
// staff-admin: crea cuentas del personal y cambia su contraseña.
//
// Necesita la clave de servicio (crear usuarios en Auth), por eso vive aquí y
// no en la app. Antes de hacer nada comprueba, CON EL TOKEN DE QUIEN LLAMA,
// que su rol tenga `staff.manage`; solo un dueño crea dueños o cambia la
// contraseña de un dueño.
//
// POST { action: "create", email, password, full_name, role, document_id?, phone?, hired_on?, notes? }
// POST { action: "set_password", user_id, password }
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const ROLES = ["owner", "admin", "reception", "trainer"];

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

function clean(v: unknown, max: number): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t.length === 0 ? null : t.slice(0, max);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "Método no permitido" });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return reply(401, { error: "Falta la sesión" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // 1. ¿Quién llama y qué puede hacer? (con SU token: aplica RLS y roles)
  const caller = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data: access, error: accessError } = await caller.rpc("my_access").maybeSingle();
  if (accessError || !access) return reply(403, { error: "Tu cuenta no está activa en el personal" });
  const me = access as { user_id: string; role: string; permissions: string[] };
  if (!me.permissions.includes("staff.manage")) return reply(403, { error: "Tu rol no puede gestionar al personal" });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reply(400, { error: "Solicitud inválida" });
  }

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  const password = typeof body.password === "string" ? body.password : "";
  if (password.length < 8 || password.length > 72) {
    return reply(400, { error: "La contraseña debe tener entre 8 y 72 caracteres" });
  }

  if (body.action === "create") {
    const email = clean(body.email, 120)?.toLowerCase();
    const fullName = clean(body.full_name, 120);
    const role = typeof body.role === "string" ? body.role : "";
    if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return reply(400, { error: "Correo inválido" });
    if (!fullName || fullName.length < 2) return reply(400, { error: "Indica el nombre completo" });
    if (!ROLES.includes(role)) return reply(400, { error: "Rol inválido" });
    if (role === "owner" && me.role !== "owner") return reply(403, { error: "Solo un dueño puede crear otro dueño" });

    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName },
    });
    if (createError || !created.user) {
      const taken = createError?.message?.toLowerCase().includes("already");
      return reply(taken ? 409 : 400, { error: taken ? "Ya existe una cuenta con ese correo" : createError?.message ?? "No se pudo crear la cuenta" });
    }

    const { error: staffError } = await admin.from("staff").insert({
      user_id: created.user.id,
      full_name: fullName,
      role,
      email,
      document_id: clean(body.document_id, 12),
      phone: clean(body.phone, 11),
      hired_on: clean(body.hired_on, 10) ?? undefined,
      notes: clean(body.notes, 2000),
    });
    if (staffError) {
      // Sin ficha no hay acceso: no dejar una cuenta huérfana.
      await admin.auth.admin.deleteUser(created.user.id);
      const msg = staffError.message.includes("staff_document_id_key")
        ? "Ya hay otra persona del personal con esa cédula"
        : staffError.message.includes("check constraint")
        ? "Revisa la cédula (V-12345678) y el teléfono (11 dígitos)"
        : staffError.message;
      return reply(400, { error: msg });
    }
    return reply(200, { user_id: created.user.id });
  }

  if (body.action === "set_password") {
    const userId = typeof body.user_id === "string" ? body.user_id : "";
    const { data: target } = await admin.from("staff").select("role").eq("user_id", userId).maybeSingle();
    if (!target) return reply(404, { error: "La persona no existe" });
    if (target.role === "owner" && me.role !== "owner") {
      return reply(403, { error: "Solo un dueño puede cambiar la contraseña de otro dueño" });
    }
    const { error } = await admin.auth.admin.updateUserById(userId, { password });
    if (error) return reply(400, { error: error.message });
    await admin.from("audit_log").insert({
      user_id: me.user_id,
      action: "staff.password",
      entity: "staff",
      entity_id: userId,
    });
    return reply(200, { ok: true });
  }

  return reply(400, { error: "Acción desconocida" });
});
