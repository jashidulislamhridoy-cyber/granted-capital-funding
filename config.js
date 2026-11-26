// Supabase connection for Granted Capital Funding (public, safe to commit:
// the anon key only allows what the Row-Level Security rules permit).
// Supabase Dashboard → Project Settings → API → copy "Project URL" and "anon public" key.
const SUPABASE_URL = '';        // e.g. 'https://abcdefghijklm.supabase.co'
const SUPABASE_ANON_KEY = '';   // e.g. 'eyJhbGciOiJIUzI1NiIsInR5cCI6...'

window.GCF_CONFIG = { SUPABASE_URL, SUPABASE_ANON_KEY };
