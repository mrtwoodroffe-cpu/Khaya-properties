# Khaya Properties: starter

Next.js 14 + Supabase (Postgres, PostGIS, auth, storage) + PayFast. This is a working core, not the full product: it covers the database, security, paid-listing flow, expiry and SEO listing pages. The visual pages come from the prototypes.

## Setup
1. Create a Supabase project (choose the Cape Town region if offered). Enable the `postgis` extension.
2. In the SQL editor run, in order: `supabase/migrations/0001_schema.sql`, `0002_security_and_payments.sql`, `0003_seed.sql`.
3. Create a Storage bucket `listing-media` (public read, owner write).
4. `cp .env.example .env.local` and fill in the Supabase keys. Keep the PayFast sandbox values for now.
5. `npm install && npm run dev`.

## Paid listing flow
`POST /api/listings` creates a draft, then `POST /api/listings/:id/checkout` records a payment at the package price and returns the PayFast form fields. The browser posts them to PayFast, and PayFast calls `/api/payments/payfast/notify`. After the signature, PayFast server check and amount check pass, `activate_listing_payment()` sets the listing live (or Pending Review, per the `auto_approve` setting) and sets its expiry. `/api/cron/expire` runs daily and expires old listings.

## Testing payments
Use PayFast sandbox. The notify URL must be public HTTPS, so deploy to Vercel or tunnel with ngrok. Confirm that a paid test listing activates and that replaying the same notification does nothing.

## Before launch
- Add the remaining pages: sign-in/up, listing wizard (call the routes above), photo upload and reorder, seller dashboard, messaging, saved-search alerts, admin queue (all RLS-ready), map search with real map tiles.
- Resume-from-pause and renewal should go through server routes (RLS blocks owners from setting `active` themselves).
- Add rate limiting on messaging and listing creation, and a malware/size check on uploads.
- Switch PayFast to live credentials and set a passphrase.
- Have a South African lawyer review Terms, Privacy (POPIA) and Listing Rules.
