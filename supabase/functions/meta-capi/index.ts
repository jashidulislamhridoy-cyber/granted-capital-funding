// =====================================================================
// meta-capi — Meta Conversions API relay for Granted Capital Funding
//
// The website POSTs each conversion here with the SAME event_id it gave
// the browser pixel, so Meta de-duplicates browser + server copies.
// This function:
//   • reads the Pixel ID (site_settings) and the CAPI token / test code
//     (private_settings, admin-only) with the service-role key
//   • SHA-256 hashes the visitor's email / phone / name as Meta requires
//   • forwards the event to the Graph API
//
// Deploy with JWT verification OFF (the site calls it with the public
// publishable key, which is not a JWT). See supabase/config.toml.
// =====================================================================
import { createClient } from "jsr:@supabase/supabase-js@2";

const GRAPH_VERSION = "v26.0"; // v21.0 is removed by Meta on 2027-01-21
const ALLOWED_EVENTS = new Set(["Lead", "SubmitApplication", "Schedule", "AffiliateClick", "Contact"]);
const CUSTOM_EVENTS = new Set(["AffiliateClick"]); // everything else is a Meta standard event

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
const clip = (v: unknown, n = 300) => (typeof v === "string" ? v.slice(0, n) : "");

async function buildUserData(u: Record<string, unknown>, req: Request) {
  const out: Record<string, unknown> = {};
  const email = clip(u.email).trim().toLowerCase();
  if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) out.em = [await sha256(email)];

  let phone = clip(u.phone).replace(/\D/g, "");
  if (phone.length === 10) phone = "1" + phone; // US numbers without country code
  if (phone.length >= 11) out.ph = [await sha256(phone)];

  const parts = clip(u.name).trim().toLowerCase().split(/\s+/).filter(Boolean)
    .map((p) => p.replace(/[^\p{L}]/gu, "")).filter(Boolean);
  if (parts.length) out.fn = [await sha256(parts[0])];
  if (parts.length > 1) out.ln = [await sha256(parts[parts.length - 1])];
  if (out.em || out.ph) out.country = [await sha256("us")];

  const ext = clip(u.external_id, 80);
  if (ext) out.external_id = [await sha256(ext)];

  const fbp = clip(u.fbp, 200), fbc = clip(u.fbc, 400);
  if (/^fb\.\d\.\d+\.\S+$/.test(fbp)) out.fbp = fbp;
  if (/^fb\.\d\.\d+\.\S+$/.test(fbc)) out.fbc = fbc;

  const ip = (req.headers.get("x-forwarded-for") || "").split(",")[0].trim();
  if (ip) out.client_ip_address = ip;
  const ua = req.headers.get("user-agent");
  if (ua) out.client_user_agent = ua.slice(0, 500);
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, error: "POST only" }, 405);
  if (Number(req.headers.get("content-length") || 0) > 8000) return json({ ok: false, error: "payload too large" }, 413);

  let body: Record<string, any>;
  try { body = await req.json(); } catch { return json({ ok: false, error: "invalid JSON" }, 400); }

  const isTest = body.test === true;
  const eventName = isTest ? "Lead" : clip(body.event_name, 40);
  const eventId = clip(body.event_id, 100) || (isTest ? "test-" + crypto.randomUUID() : "");
  if (!ALLOWED_EVENTS.has(eventName)) return json({ ok: false, error: "event not allowed" }, 400);
  if (!eventId) return json({ ok: false, error: "event_id required" }, 400);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const [pub, priv] = await Promise.all([
    admin.from("site_settings").select("value").eq("key", "meta_pixel_id").maybeSingle(),
    admin.from("private_settings").select("key,value").in("key", ["meta_capi_token", "meta_test_event_code"]),
  ]);
  const pixelId = (pub.data?.value || "").trim();
  const secrets = Object.fromEntries((priv.data || []).map((r) => [r.key, (r.value || "").trim()]));
  const token = secrets.meta_capi_token || "";
  const testCode = secrets.meta_test_event_code || "";

  if (!/^\d{8,20}$/.test(pixelId) || !token) {
    return json({ ok: false, skipped: true, error: "CAPI not configured (needs Meta Pixel ID + CAPI token)" });
  }
  if (isTest && !testCode) {
    return json({ ok: false, error: "Add a Test Event Code first so the test does not count as a real lead." });
  }

  const user = isTest
    ? { email: "capi-test@grantedcapital.example", name: "CAPI Test", external_id: "admin-test" }
    : (body.user || {});
  const custom = (body.custom_data && typeof body.custom_data === "object") ? body.custom_data : {};
  const customData: Record<string, string> = {};
  for (const [k, v] of Object.entries(custom).slice(0, 10)) {
    if (["string", "number", "boolean"].includes(typeof v)) customData[k.slice(0, 40)] = String(v).slice(0, 120);
  }

  const event = {
    event_name: eventName,
    event_time: Math.floor(Date.now() / 1000),
    event_id: eventId,
    action_source: "website",
    event_source_url: clip(body.event_source_url, 500) || undefined,
    user_data: await buildUserData(user, req),
    custom_data: Object.keys(customData).length ? customData : undefined,
  };
  const payload: Record<string, unknown> = { data: [event] };
  if (testCode) payload.test_event_code = testCode; // while set, events show only in Events Manager › Test Events

  const res = await fetch(
    `https://graph.facebook.com/${GRAPH_VERSION}/${pixelId}/events?access_token=${encodeURIComponent(token)}`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) },
  );
  const meta = await res.json().catch(() => ({}));
  return json({
    ok: res.ok,
    event_name: eventName,
    event_id: eventId,
    test_mode: !!testCode,
    events_received: meta.events_received,
    fbtrace_id: meta.fbtrace_id,
    error: res.ok ? undefined : (meta.error?.message || `Meta returned ${res.status}`),
  }, res.ok ? 200 : 502);
});
