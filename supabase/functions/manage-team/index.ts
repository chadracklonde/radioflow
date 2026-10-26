// Radio Flow : gestion de l'équipe (réservée au super administrateur).
// La clé de service ne quitte jamais le serveur : l'application appelle cette fonction avec la
// session de l'utilisateur, et la fonction vérifie elle-même que l'appelant est le super administrateur.
//
// Actions (POST, JSON) :
//   { "action": "create", "email": "...", "full_name": "...", "role": "journalist" }
//        -> { id, email, temp_password }   (le mot de passe provisoire n'est renvoyé qu'une fois)
//   { "action": "deactivate", "id": "<uuid>" }
//   { "action": "reactivate", "id": "<uuid>" }
//   { "action": "reset_password", "id": "<uuid>" }
//        -> { id, email, temp_password }   (nouveau mot de passe provisoire, renvoyé une seule fois)
import { createClient } from "npm:@supabase/supabase-js@2";

const ROLES = ["admin", "journalist", "technician"];
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

/** 16 caractères sans ambiguïté visuelle (ni 0/O ni 1/l/I), avec au moins une lettre et un chiffre. */
function tempPassword(): string {
  const letters = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz";
  const digits = "23456789";
  const all = letters + digits;
  const pick = (set: string) => {
    // tirage sans biais (rejet des valeurs hors du plus grand multiple de la taille)
    const limit = 256 - (256 % set.length);
    for (;;) {
      const b = crypto.getRandomValues(new Uint8Array(1))[0];
      if (b < limit) return set[b % set.length];
    }
  };
  const chars = Array.from({ length: 14 }, () => pick(all));
  chars.push(pick(letters), pick(digits));
  for (let i = chars.length - 1; i > 0; i--) {
    const j = Math.floor((crypto.getRandomValues(new Uint32Array(1))[0] / 2 ** 32) * (i + 1));
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Méthode non autorisée." });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // 1. Qui appelle ?
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: session, error: sessionError } = await admin.auth.getUser(token);
  if (sessionError || !session.user) return json(401, { error: "Session invalide. Reconnectez-vous." });

  // 2. Est-ce le super administrateur (actif) ?
  const { data: me } = await admin
    .from("users")
    .select("is_super_admin, active")
    .eq("id", session.user.id)
    .maybeSingle();
  if (!me || !me.is_super_admin || !me.active) {
    return json(403, { error: "Action réservée au super administrateur." });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "Requête illisible." });
  }

  switch (body.action) {
    case "create": {
      const email = String(body.email ?? "").trim().toLowerCase();
      const fullName = String(body.full_name ?? "").trim();
      const role = String(body.role ?? "journalist");
      if (!EMAIL.test(email)) return json(400, { error: "Email invalide." });
      if (fullName.length < 2 || fullName.length > 100) {
        return json(400, { error: "Le nom doit faire entre 2 et 100 caractères." });
      }
      if (!ROLES.includes(role)) return json(400, { error: "Rôle inconnu." });

      const password = tempPassword();
      const { data: created, error: createError } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { full_name: fullName },
      });
      if (createError || !created.user) {
        const exists = /already|registered|exists/i.test(createError?.message ?? "");
        return exists
          ? json(409, { error: "Un compte existe déjà avec cet email." })
          : json(500, { error: "Création impossible. Réessayez." });
      }

      // Le profil est créé par un déclencheur (rôle « journalist »); on applique le rôle demandé.
      if (role !== "journalist") {
        const { error: roleError } = await admin.from("users").update({ role }).eq("id", created.user.id);
        if (roleError) {
          await admin.auth.admin.deleteUser(created.user.id); // pas de compte à moitié créé
          return json(500, { error: "Création impossible. Réessayez." });
        }
      }
      return json(200, { id: created.user.id, email, temp_password: password });
    }

    case "deactivate":
    case "reactivate": {
      const id = String(body.id ?? "");
      if (!UUID.test(id)) return json(400, { error: "Identifiant invalide." });
      const deactivate = body.action === "deactivate";
      if (deactivate && id === session.user.id) {
        return json(400, { error: "Vous ne pouvez pas désactiver votre propre compte." });
      }

      // Le compte super administrateur ne se désactive pas.
      const { data: target } = await admin.from("users").select("is_super_admin").eq("id", id).maybeSingle();
      if (!target) return json(404, { error: "Membre introuvable." });
      if (deactivate && target.is_super_admin) {
        return json(400, { error: "Le compte super administrateur ne peut pas être désactivé." });
      }

      // Le profil d'abord : un déclencheur refuse de désactiver le dernier administrateur.
      const { error: flagError } = await admin.from("users").update({ active: !deactivate }).eq("id", id);
      if (flagError) {
        return json(409, { error: flagError.message.includes("administrateur")
          ? "Il doit rester au moins un administrateur actif."
          : "Mise à jour impossible." });
      }
      const { error: banError } = await admin.auth.admin.updateUserById(id, {
        ban_duration: deactivate ? "876000h" : "none",
      });
      if (banError) {
        await admin.from("users").update({ active: deactivate }).eq("id", id); // on annule
        return json(500, { error: "Mise à jour impossible. Réessayez." });
      }
      return json(200, { id, active: !deactivate });
    }

    case "reset_password": {
      const id = String(body.id ?? "");
      if (!UUID.test(id)) return json(400, { error: "Identifiant invalide." });
      if (id === session.user.id) {
        return json(400, { error: "Changez votre propre mot de passe depuis Mon compte." });
      }
      const { data: target } = await admin
        .from("users")
        .select("email, is_super_admin")
        .eq("id", id)
        .maybeSingle();
      if (!target) return json(404, { error: "Membre introuvable." });
      if (target.is_super_admin) {
        return json(400, { error: "Le mot de passe du super administrateur ne se réinitialise pas ici." });
      }
      const password = tempPassword();
      const { error: updateError } = await admin.auth.admin.updateUserById(id, { password });
      if (updateError) return json(500, { error: "Réinitialisation impossible. Réessayez." });
      return json(200, { id, email: target.email, temp_password: password });
    }

    default:
      return json(400, { error: "Action inconnue." });
  }
});
