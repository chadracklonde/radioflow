// Radio Flow : envoi des notifications push (Firebase Cloud Messaging, API HTTP v1).
//
// Déployée avec verify_jwt = false (voir supabase/push_setup.sql). Appelée par un déclencheur de la base à chaque nouvelle notification (voir
// supabase/push_setup.sql) avec { "id": "<uuid de la notification>" }.
//
// - L'identifiant seul suffit : le titre, le texte et le destinataire sont relus dans la base
//   avec la clé de service. Appeler la fonction avec un identifiant inconnu ne fait rien.
// - Chaque notification n'est envoyée qu'une fois (colonne pushed_at, prise de façon atomique) :
//   un second appel ne renvoie rien, même en cas de répétition.
// - Si le secret FCM_SERVICE_ACCOUNT n'est pas défini, rien n'est envoyé et rien n'est consommé :
//   les notifications restent disponibles dans l'application.
import { createClient } from "npm:@supabase/supabase-js@2";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

type ServiceAccount = { project_id: string; client_email: string; private_key: string };

const b64url = (data: ArrayBuffer | string): string => {
  const bytes = typeof data === "string"
    ? new TextEncoder().encode(data)
    : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

/** Jeton d'accès Google (OAuth2, compte de service) pour l'API FCM. */
async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key
    .replace(/-----(BEGIN|END) [A-Z ]+-----/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const assertion = `${header}.${claims}.${b64url(signature)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`Jeton Google refusé (${res.status})`);
  const data = await res.json() as { access_token: string };
  return data.access_token;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { error: "Méthode non autorisée." });

  let id = "";
  try {
    const body = await req.json() as { id?: unknown; record?: { id?: unknown } };
    id = String(body.id ?? body.record?.id ?? "");
  } catch {
    return json(400, { error: "Requête illisible." });
  }
  if (!UUID.test(id)) return json(400, { error: "Identifiant invalide." });

  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) return json(200, { skipped: "FCM non configuré" });
  let sa: ServiceAccount;
  try {
    sa = JSON.parse(raw) as ServiceAccount;
  } catch {
    return json(500, { error: "FCM_SERVICE_ACCOUNT n'est pas un JSON valide." });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // Prise atomique : une seule exécution envoie cette notification.
  const { data: claimed, error: claimError } = await admin
    .from("notifications")
    .update({ pushed_at: new Date().toISOString() })
    .eq("id", id)
    .is("pushed_at", null)
    .select("id, user_id, kind, title, body, ref_type, ref_id")
    .maybeSingle();
  if (claimError) return json(500, { error: "Lecture impossible." });
  if (!claimed) return json(200, { skipped: "déjà envoyée ou inconnue" });

  const { data: devices } = await admin
    .from("device_tokens")
    .select("token")
    .eq("user_id", claimed.user_id);
  const tokens = (devices ?? []).map((d: { token: string }) => d.token);
  if (tokens.length === 0) return json(200, { sent: 0 });

  let bearer: string;
  try {
    bearer = await accessToken(sa);
  } catch (e) {
    // On rend la notification à nouveau envoyable.
    await admin.from("notifications").update({ pushed_at: null }).eq("id", id);
    return json(502, { error: String(e) });
  }

  let sent = 0;
  const dead: string[] = [];
  for (const token of tokens) {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: "POST",
        headers: { "Authorization": `Bearer ${bearer}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: claimed.title, body: claimed.body ?? "" },
            data: {
              notification_id: claimed.id,
              kind: claimed.kind,
              ref_type: claimed.ref_type ?? "",
              ref_id: claimed.ref_id ?? "",
            },
            android: { priority: "HIGH" },
            apns: { payload: { aps: { sound: "default" } } },
          },
        }),
      },
    );
    if (res.ok) {
      sent++;
    } else if (res.status === 404 || res.status === 400) {
      dead.push(token); // appareil désinstallé ou jeton périmé
    }
  }
  if (dead.length > 0) {
    await admin.from("device_tokens").delete().in("token", dead);
  }
  return json(200, { sent, removed: dead.length });
});
