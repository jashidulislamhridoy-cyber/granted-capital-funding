// Supabase connection for Granted Capital Funding (public, safe to commit:
// the anon key only allows what the Row-Level Security rules permit).
// Supabase Dashboard → Project Settings → API → copy the Project URL and the Publishable key (never the secret / service_role key).
const SUPABASE_URL = 'https://rpvxgdxqosxlfxiuadwo.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable__owYiMIIiVU2Bm6kKoq7hQ_B5h07OkO';   // publishable (browser-safe) key

window.GCF_CONFIG = { SUPABASE_URL, SUPABASE_ANON_KEY };
