-- =====================================================================
--  GRANTED CAPITAL FUNDING — Supabase setup (run once in SQL Editor)
--  Safe to re-run: tables use IF NOT EXISTS, policies are recreated,
--  and seed rows are only inserted into empty tables.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0) ADMIN ALLOW-LIST  >>> EDIT THE EMAIL BELOW BEFORE RUNNING <<<
--    Only emails listed here can edit content or read leads/analytics,
--    even if someone else manages to create a Supabase Auth account.
-- ---------------------------------------------------------------------
create table if not exists public.admin_users (
  email      text primary key,
  created_at timestamptz not null default now()
);
alter table public.admin_users enable row level security;   -- no policies: not readable via the API

insert into public.admin_users (email) values
  ('YOUR_ADMIN_EMAIL@example.com')          -- <<< replace with the email you will log in with
on conflict (email) do nothing;

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admin_users a
    where lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
grant execute on function public.is_admin() to anon, authenticated;

-- ---------------------------------------------------------------------
-- 1) TABLES
-- ---------------------------------------------------------------------
create table if not exists public.site_settings (
  key        text primary key,
  value      text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists public.proof_gallery (
  id         bigint generated always as identity primary key,
  sort_order int  not null default 0,
  title      text not null,
  amount     text not null default '',
  category   text not null default 'Exotic Cars'
             check (category in ('Exotic Cars','Real Estate & Homes','Bank Approvals')),
  client     text not null default '',
  image_url  text not null default '',
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.client_reviews (
  id         bigint generated always as identity primary key,
  sort_order int  not null default 0,
  name       text not null,
  business   text not null default '',
  amount     text not null default '',
  stars      int  not null default 5 check (stars between 1 and 5),
  text       text not null,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.faqs (
  id          bigint generated always as identity primary key,
  sort_order  int  not null default 0,
  question    text not null,
  answer_html text not null,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.leads (
  id            uuid primary key default gen_random_uuid(),
  created_at    timestamptz not null default now(),
  source        text not null check (source in ('prequal','checklist','vault')),
  status        text not null default 'New Lead'
                check (status in ('New Lead','Call Booked','In Review','Approved','Funded')),
  name          text check (char_length(name)     <= 200),
  email         text check (char_length(email)    <= 200),
  phone         text check (char_length(phone)    <= 60),
  business      text check (char_length(business) <= 200),
  program       text check (char_length(program)  <= 120),
  credit_tier   text check (char_length(credit_tier)   <= 40),
  llc_status    text check (char_length(llc_status)    <= 80),
  target_amount text check (char_length(target_amount) <= 40),
  document_path text check (char_length(document_path) <= 400),
  document_name text check (char_length(document_name) <= 260),
  notes         text,
  session_id    text check (char_length(session_id)   <= 80),
  utm_source    text check (char_length(utm_source)   <= 200),
  utm_medium    text check (char_length(utm_medium)   <= 200),
  utm_campaign  text check (char_length(utm_campaign) <= 200),
  utm_content   text check (char_length(utm_content)  <= 200),
  fbclid        text check (char_length(fbclid)       <= 300),
  gclid         text check (char_length(gclid)        <= 300),
  landing_page  text check (char_length(landing_page) <= 400),
  referrer      text check (char_length(referrer)     <= 400)
);
create index if not exists leads_created_idx on public.leads (created_at desc);

create table if not exists public.analytics_events (
  id           bigint generated always as identity primary key,
  created_at   timestamptz not null default now(),
  event_name   text not null
               check (event_name in ('PageView','Lead','SubmitApplication','Schedule','AffiliateClick','Contact','TestEvent')),
  session_id   text check (char_length(session_id)   <= 80),
  page         text check (char_length(page)         <= 400),
  utm_source   text check (char_length(utm_source)   <= 200),
  utm_medium   text check (char_length(utm_medium)   <= 200),
  utm_campaign text check (char_length(utm_campaign) <= 200),
  utm_content  text check (char_length(utm_content)  <= 200),
  fbclid       text check (char_length(fbclid)       <= 300),
  gclid        text check (char_length(gclid)        <= 300),
  metadata     jsonb not null default '{}'::jsonb check (pg_column_size(metadata) <= 4000)
);
create index if not exists analytics_created_idx on public.analytics_events (created_at desc);
create index if not exists analytics_name_idx    on public.analytics_events (event_name, created_at desc);

-- ---------------------------------------------------------------------
-- 2) ROW-LEVEL SECURITY
--    Content tables: anyone can read, only admins can write.
--    leads / analytics_events: anyone can INSERT, only admins can read/edit.
-- ---------------------------------------------------------------------
alter table public.site_settings    enable row level security;
alter table public.proof_gallery    enable row level security;
alter table public.client_reviews   enable row level security;
alter table public.faqs             enable row level security;
alter table public.leads            enable row level security;
alter table public.analytics_events enable row level security;

do $$
declare t text;
begin
  foreach t in array array['site_settings','proof_gallery','client_reviews','faqs'] loop
    execute format('drop policy if exists "public read" on public.%I', t);
    execute format('drop policy if exists "admin write" on public.%I', t);
    execute format('create policy "public read" on public.%I for select to anon, authenticated using (true)', t);
    execute format('create policy "admin write" on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

drop policy if exists "public insert lead" on public.leads;
drop policy if exists "admin read leads"   on public.leads;
drop policy if exists "admin update leads" on public.leads;
drop policy if exists "admin delete leads" on public.leads;
create policy "public insert lead" on public.leads for insert to anon, authenticated
  with check (status = 'New Lead' and notes is null);
create policy "admin read leads"   on public.leads for select to authenticated using (public.is_admin());
create policy "admin update leads" on public.leads for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin delete leads" on public.leads for delete to authenticated using (public.is_admin());

drop policy if exists "public insert event"  on public.analytics_events;
drop policy if exists "admin read events"    on public.analytics_events;
drop policy if exists "admin delete events"  on public.analytics_events;
create policy "public insert event" on public.analytics_events for insert to anon, authenticated with check (true);
create policy "admin read events"   on public.analytics_events for select to authenticated using (public.is_admin());
create policy "admin delete events" on public.analytics_events for delete to authenticated using (public.is_admin());

grant select on public.site_settings, public.proof_gallery, public.client_reviews, public.faqs to anon, authenticated;
grant insert on public.leads, public.analytics_events to anon, authenticated;
grant select, insert, update, delete on public.site_settings, public.proof_gallery, public.client_reviews,
      public.faqs, public.leads, public.analytics_events to authenticated;
grant usage, select on all sequences in schema public to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) STORAGE
--    site-media : PUBLIC bucket for logo, portrait, gallery photos, MP4s.
--    vault-docs : PRIVATE bucket for client credit reports / IDs.
--                 Visitors can upload into uploads/ but nobody can list or
--                 download except admins (via short-lived signed links).
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('site-media', 'site-media', true, 52428800)
on conflict (id) do update set public = true;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('vault-docs', 'vault-docs', false, 26214400, array['application/pdf','image/png','image/jpeg'])
on conflict (id) do update set public = false,
  file_size_limit = 26214400,
  allowed_mime_types = array['application/pdf','image/png','image/jpeg'];

drop policy if exists "site-media public read"   on storage.objects;
drop policy if exists "site-media admin insert"  on storage.objects;
drop policy if exists "site-media admin update"  on storage.objects;
drop policy if exists "site-media admin delete"  on storage.objects;
drop policy if exists "vault public upload"      on storage.objects;
drop policy if exists "vault admin read"         on storage.objects;
drop policy if exists "vault admin delete"       on storage.objects;

create policy "site-media public read"  on storage.objects for select to anon, authenticated
  using (bucket_id = 'site-media');
create policy "site-media admin insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'site-media' and public.is_admin());
create policy "site-media admin update" on storage.objects for update to authenticated
  using (bucket_id = 'site-media' and public.is_admin());
create policy "site-media admin delete" on storage.objects for delete to authenticated
  using (bucket_id = 'site-media' and public.is_admin());

create policy "vault public upload" on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'vault-docs' and (storage.foldername(name))[1] = 'uploads');
create policy "vault admin read"    on storage.objects for select to authenticated
  using (bucket_id = 'vault-docs' and public.is_admin());
create policy "vault admin delete"  on storage.objects for delete to authenticated
  using (bucket_id = 'vault-docs' and public.is_admin());

-- ---------------------------------------------------------------------
-- 4) SEED DATA (current website content)
-- ---------------------------------------------------------------------

insert into public.site_settings (key, value) values
  ('hero_badge', 'EXCLUSIVE FOR US LLCs & ENTREPRENEURS • 680+ CREDIT SCORE'),
  ('hero_headline_html', 'Unlock <span class="text-gold-gradient">$50,000 – $150,000+</span> in <span class="underline decoration-gold/60 underline-offset-8">0% APR</span> Business Funding'),
  ('hero_subtitle_html', 'Scale your company, acquire luxury assets, or fuel cash flow with <strong class="text-white">12–18 months of 0% interest capital</strong>. Zero collateral, zero tax returns, and zero upfront equity required.'),
  ('founder_bio_html', 'Aaron Lee is the Founder &amp; Chief Capital Strategist of <strong class="text-white">Granted Capital Funding</strong> (<em class="text-gold-light">By Aaron Lee Enterprises</em>). He specializes in helping US entrepreneurs and active LLC owners secure <strong class="text-white">$50,000 – $150,000+ in 0% APR corporate funding</strong> without collateral or tax returns, alongside <strong class="text-white">Credit Restoration</strong> and <strong class="text-white">Credit to Keys</strong> mortgage readiness.'),
  ('footer_disclosure_html', '<strong class="text-zinc-400">CROA &amp; Regulatory Disclosure:</strong> Granted Capital Funding (by Aaron Lee Enterprises, formerly Guaranteed Capital &amp; Credit) operates as a credit services organization subject to the Credit Repair Organizations Act (CROA). You have the right to dispute inaccurate information in your credit report directly with consumer reporting agencies at no charge. Granted Capital Funding is not a direct bank or financial lender; all 0% APR corporate funding ($50,000–$150,000+ for 12–18 months) is subject to third-party bank underwriting, personal credit profile (680+ FICO), and active US LLC standing. <strong class="text-zinc-400">Affiliate Disclosure:</strong> Granted Capital Funding may earn a commission when you sign up for MyScoreIQ through our links, at no additional cost to you.'),
  ('contact_phone', '+1 (210) 774-1154'),
  ('contact_email', 'aaronleeenterprises@gmail.com'),
  ('calendly_url', 'https://calendly.com/guaranteedcapitalandcredit'),
  ('myscoreiq_url', 'https://www.myscoreiq.com/get-fico-preferred.aspx?offercode=432142YU'),
  ('founder_photo_url', 'image_7487d3.jpg?v=2'),
  ('founder_video_url', 'aron-about.mp4'),
  ('founder_video_poster_url', ''),
  ('brand_logo_url', 'brand-logo.png'),
  ('social_youtube', 'https://www.youtube.com/@Aaronlee_enterprises/videos'),
  ('social_instagram', 'https://www.instagram.com/guaranteedcap1/reels/'),
  ('social_facebook', 'https://www.facebook.com/guaranteedcapital'),
  ('social_linkedin', 'https://www.linkedin.com/in/aaron-lee-72716719b/'),
  ('social_tiktok', 'https://www.tiktok.com/@guaranteedcapandcred'),
  ('meta_pixel_id', ''),
  ('gtm_id', ''),
  ('ga4_id', ''),
  ('gads_conversion_id', ''),
  ('gads_conversion_label', ''),
  ('tiktok_pixel_id', ''),
  ('custom_head_scripts', '')
on conflict (key) do nothing;

insert into public.proof_gallery (sort_order, title, amount, category, client, image_url)
select * from (values
  (1, 'Bugatti Chiron Pur Sport', '$150,000 @ 0% APR', 'Exotic Cars', 'Miami Exotic Rentals LLC • Funded in 11 Days', 'proof-01.png'),
  (2, 'Chase Ink Business Premier', '$85,000 Approved', 'Bank Approvals', 'Apex E-Commerce Group LLC • 0% Intro APR', 'proof-05.png'),
  (3, 'Modern Poolside Luxury Villa', '724 FICO • Closed', 'Real Estate & Homes', 'Credit to Keys Program • Mortgage Ready', 'proof-03.png'),
  (4, 'Mercedes-AMG G63 Wagon', '$150,000 @ 0% APR', 'Exotic Cars', 'Vanguard Executive Fleet LLC • 18 Mos 0%', 'proof-04.png'),
  (5, 'Amex Business Gold & Platinum Stack', '$115,000 Combined', 'Bank Approvals', 'Titan Logistics Holdings LLC • Zero Tax Returns', 'proof-08.png'),
  (6, 'Porsche Panamera Turbo S', '$130,000 @ 0% APR', 'Exotic Cars', 'Scottsdale Luxury Holdings LLC • 12 Days', 'proof-06.png'),
  (7, 'Contemporary White Estate', '$120,000 Rehab Line', 'Real Estate & Homes', 'BRRRR Capital Partners LLC • 0% APR Stacking', 'proof-07.png'),
  (8, 'U.S. Bank Triple Cash Corporate Line', '$95,000 Approved • Zero Tax Returns', 'Bank Approvals', 'Summit MedSpa Ventures LLC • 15 Mos 0% APR', 'proof-11.png'),
  (9, 'Rolls-Royce Wraith Black Badge', '$150,000+ Stack', 'Exotic Cars', 'Crown Chauffeur Concierge LLC • Houston, TX', 'proof-09.png'),
  (10, 'Palm-Lined Executive Residence', '718 FICO • Approved', 'Real Estate & Homes', 'Credit to Keys Underwriting • Closed in 30 Days', 'proof-10.png'),
  (11, 'Truist & PNC Multi-Bank Stack', '$110,000 @ 0% APR', 'Bank Approvals', 'NextGen Solar Solutions LLC • Unsecured', 'proof-02.png'),
  (12, 'Ferrari F8 Tributo Acquisition', '$140,000 @ 0% APR', 'Exotic Cars', 'Prestige Auto Group LLC • Zero Collateral', 'proof-12.png')
) as v(sort_order, title, amount, category, client, image_url)
where not exists (select 1 from public.proof_gallery);

insert into public.client_reviews (sort_order, name, business, amount, stars, text)
select * from (values
  (1, 'Marcus T.', 'Freight Operator', 'Equipment Funded', 5, 'Two collections removed in five weeks, and got logistics equipment funding right after.'),
  (2, 'Elena & David R.', 'Homeowners • Credit to Keys', '700+ Score', 5, 'Credit to Keys program raised my score above 700. We just closed on our family home!'),
  (3, 'Jason K.', 'E-Commerce Founder', '$65,000 @ 0% APR', 5, 'The audit was incredible. Secured a $65k unsecured line of credit within weeks.'),
  (4, 'Derrick Vance', 'Vance Luxury Fleet LLC', '$145,000 @ 0% APR', 5, 'Aaron Lee structured our multi-bank stack in 12 days flat. We secured $145K at 0% APR for 18 months with zero tax returns and added two exotic vehicles to our fleet.'),
  (5, 'Sophia Martinez', 'Aura Aesthetics LLC', '$110,000 @ 0% APR', 5, 'Banks turned us down for months because our LLC was under a year old. Granted Capital Funding got us $110K at 0% interest without touching our personal DTI.'),
  (6, 'Brandon Brooks', 'Brooks Property Group LLC', '$150,000 @ 0% APR', 5, 'Transparent, fast, and institutional-grade execution. Having $150K at 0% APR allowed us to renovate two properties simultaneously without paying 14% hard money rates.')
) as v(sort_order, name, business, amount, stars, text)
where not exists (select 1 from public.client_reviews);

insert into public.faqs (sort_order, question, answer_html)
select * from (values
  (1, 'What are the exact requirements to qualify for $50K–$150K+ at 0% APR?', 'To qualify, you need a <strong class="text-white">680+ personal credit score</strong> across Experian, Equifax, and TransUnion, low personal credit utilization (ideally under 30%), and an <strong class="text-white">active US LLC</strong> (or Corporation) in good standing. No tax returns, bank statements, or collateral are required.
<span class="block mt-3 pt-3 border-t border-white/5">Don''t have a 680+ score yet? If your business generates at least <strong class="text-gold-light">$10,000/month in revenue</strong>, ask about our <strong class="text-white">No Minimum Credit Score</strong> revenue-based funding options during your strategy call.</span>'),
  (2, 'How does 0% APR corporate credit stacking work?', 'Instead of applying to one bank and getting a small limit, we strategically sequence multiple Tier-1 business credit card and line-of-credit applications across different credit bureaus within a precise window. Each approved account carries a <strong class="text-white">0% introductory APR for 12 to 18 months</strong>, stacking together to reach $50,000 to $150,000+.'),
  (3, 'Will checking my eligibility hurt my personal credit score?', 'No. Our initial pre-qualification and strategy review uses a <strong class="text-white">soft credit pull</strong> which has zero impact on your FICO score. Furthermore, once funded, these corporate accounts report strictly to your business credit profile—keeping your personal utilization clean.'),
  (4, 'What can I use the 0% APR business funding for?', 'There are <strong class="text-white">zero restrictions</strong> on how you deploy your capital. Clients routinely use their 0% APR funds for inventory, digital marketing, real estate renovations, Turo/exotic rental fleet vehicles, equipment, or payroll expansion. We also show you how to liquidate lines into cash if needed.'),
  (5, 'What if my credit score is below 680 or I am preparing to buy a home?', 'If your personal score is currently below 680, our <strong class="text-white">Credit Restoration Program</strong> performs structured tri-bureau dispute auditing and inquiry/late-payment optimization to push your score into the 680–700+ funding zone. If you are purchasing property, our <strong class="text-white">Credit to Keys Program</strong> aligns your credit profile directly with mortgage underwriting guidelines. You can pull your 3-bureau report anytime via <a href="https://www.myscoreiq.com/get-fico-preferred.aspx?offercode=432142YU" target="_blank" rel="noopener noreferrer" class="text-gold underline">MyScoreIQ</a>.')
) as v(sort_order, question, answer_html)
where not exists (select 1 from public.faqs);


-- Done. Next: Authentication > Users > Add user (same email as admin_users), and turn OFF 'Allow new users to sign up'.
