-- Khaya Properties: PostgreSQL schema (with PostGIS for map and radius search)
-- Everything an admin should change lives in data (settings, packages, categories, locations), not code.

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ENUMS
CREATE TYPE listing_mode   AS ENUM ('sale','rent','rent_to_buy');
CREATE TYPE listing_status AS ENUM ('draft','payment_pending','pending_review','active','rejected','expired','suspended','paused');
CREATE TYPE seller_type    AS ENUM ('private_owner','estate_agent','landlord','developer','property_company');
CREATE TYPE verify_level   AS ENUM ('none','owner','agent','developer','business');
CREATE TYPE verify_status  AS ENUM ('pending','approved','rejected');
CREATE TYPE payment_status AS ENUM ('initiated','pending','paid','failed','refunded');
CREATE TYPE report_reason  AS ENUM ('fake_property','scam','incorrect_info','duplicate','inappropriate','fraudulent_seller','wrong_price','unavailable');
CREATE TYPE report_status  AS ENUM ('open','investigating','actioned','dismissed');
CREATE TYPE user_role      AS ENUM ('user','moderator','admin');

-- USERS AND VERIFICATION
CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         text UNIQUE NOT NULL,
  phone         text,                       -- never exposed to other users unless seller opts in
  full_name     text NOT NULL,
  avatar_url    text,
  role          user_role NOT NULL DEFAULT 'user',
  seller_type   seller_type,
  verify_level  verify_level NOT NULL DEFAULT 'none',
  is_blocked    boolean NOT NULL DEFAULT false,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE verification_requests (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  level        verify_level NOT NULL,
  documents    jsonb NOT NULL DEFAULT '[]',   -- storage keys, kept private
  status       verify_status NOT NULL DEFAULT 'pending',
  reviewed_by  uuid REFERENCES users(id),
  admin_note   text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  reviewed_at  timestamptz
);

-- ADMIN-MANAGED REFERENCE DATA
CREATE TABLE categories (
  id         serial PRIMARY KEY,
  slug       text UNIQUE NOT NULL,           -- house, apartment, vacant-land...
  name       text NOT NULL,
  sort_order int NOT NULL DEFAULT 0,
  is_active  boolean NOT NULL DEFAULT true
);

CREATE TABLE locations (                     -- province > city > suburb, add more from admin
  id         serial PRIMARY KEY,
  parent_id  int REFERENCES locations(id),
  slug       text UNIQUE NOT NULL,           -- sandton, cape-town...
  name       text NOT NULL,
  kind       text NOT NULL CHECK (kind IN ('province','city','suburb')),
  center     geography(Point,4326),
  seo_intro  text,                           -- copy for the landing page
  is_active  boolean NOT NULL DEFAULT true
);

CREATE TABLE features (                      -- pool, garage, solar, fibre...
  id    serial PRIMARY KEY,
  slug  text UNIQUE NOT NULL,
  name  text NOT NULL,
  icon  text
);

CREATE TABLE packages (                      -- R99 / R199 / R399 are rows, not constants
  id              serial PRIMARY KEY,
  name            text NOT NULL,
  price_cents     int NOT NULL CHECK (price_cents >= 0),
  duration_days   int NOT NULL DEFAULT 30,
  is_featured     boolean NOT NULL DEFAULT false,
  homepage_slot   boolean NOT NULL DEFAULT false,
  search_boost    int NOT NULL DEFAULT 0,    -- higher ranks first, always labelled Promoted
  is_active       boolean NOT NULL DEFAULT true
);

CREATE TABLE settings (                      -- auto_approve, max_photos, vat_rate, currency...
  key         text PRIMARY KEY,
  value       jsonb NOT NULL,
  updated_by  uuid REFERENCES users(id),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- LISTINGS
CREATE TABLE listings (
  id               bigserial PRIMARY KEY,
  slug             text UNIQUE NOT NULL,     -- 4-bedroom-house-sandton-gauteng-12345
  owner_id         uuid NOT NULL REFERENCES users(id),
  seller_type      seller_type NOT NULL,
  mode             listing_mode NOT NULL,
  category_id      int NOT NULL REFERENCES categories(id),
  location_id      int NOT NULL REFERENCES locations(id),
  title            text NOT NULL,
  description      text NOT NULL,
  price_cents      bigint NOT NULL CHECK (price_cents > 0),
  previous_price_cents bigint,               -- drives "Recently Reduced"
  bedrooms         smallint, bathrooms numeric(3,1), parking smallint,
  floor_size_m2    int, land_size_m2 int,
  rates_cents      int, levies_cents int,
  furnished        boolean, pet_friendly boolean,
  is_new_development boolean NOT NULL DEFAULT false,
  street_address   text,                     -- private
  show_exact_address boolean NOT NULL DEFAULT false,
  exact_point      geography(Point,4326),    -- private
  public_point     geography(Point,4326),    -- jittered/approximate, safe for map + API
  video_url        text, virtual_tour_url text,
  status           listing_status NOT NULL DEFAULT 'draft',
  package_id       int REFERENCES packages(id),
  featured_until   timestamptz,
  published_at     timestamptz,
  expires_at       timestamptz,
  rejection_reason text,
  views_count      int NOT NULL DEFAULT 0,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX listings_browse ON listings (status, mode, category_id, location_id, price_cents);
CREATE INDEX listings_geo    ON listings USING gist (public_point);
CREATE INDEX listings_text   ON listings USING gin ((title || ' ' || description) gin_trgm_ops);
CREATE INDEX listings_expiry ON listings (expires_at) WHERE status = 'active';

CREATE TABLE listing_features (
  listing_id bigint REFERENCES listings(id) ON DELETE CASCADE,
  feature_id int REFERENCES features(id),
  PRIMARY KEY (listing_id, feature_id)
);

CREATE TABLE listing_media (
  id          bigserial PRIMARY KEY,
  listing_id  bigint NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
  kind        text NOT NULL CHECK (kind IN ('photo','video')),
  storage_key text NOT NULL,
  position    int NOT NULL DEFAULT 0,        -- drag-to-reorder
  is_cover    boolean NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX one_cover_per_listing ON listing_media (listing_id) WHERE is_cover;

CREATE TABLE moderation_events (             -- full audit trail of every status change
  id          bigserial PRIMARY KEY,
  listing_id  bigint NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
  actor_id    uuid REFERENCES users(id),
  from_status listing_status, to_status listing_status NOT NULL,
  note        text,                          -- includes "request more info"
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- PAYMENTS (listing activates only when a verified webhook sets status = 'paid')
CREATE TABLE payments (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES users(id),
  listing_id     bigint NOT NULL REFERENCES listings(id),
  package_id     int NOT NULL REFERENCES packages(id),
  amount_cents   int NOT NULL,               -- snapshot of price at purchase
  gateway        text NOT NULL,              -- payfast / peach / ozow
  gateway_ref    text UNIQUE,                -- idempotency key for webhooks
  status         payment_status NOT NULL DEFAULT 'initiated',
  paid_at        timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now()
);

-- BUYER / TENANT FEATURES
CREATE TABLE favourites (
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  listing_id bigint REFERENCES listings(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, listing_id)
);

CREATE TABLE saved_searches (                -- "3-bed house under R2m in Sandton"
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  filters    jsonb NOT NULL,
  notify     boolean NOT NULL DEFAULT true,
  last_sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE recently_viewed (
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  listing_id bigint REFERENCES listings(id) ON DELETE CASCADE,
  viewed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, listing_id)
);

-- MESSAGING
CREATE TABLE conversations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id  bigint NOT NULL REFERENCES listings(id),
  buyer_id    uuid NOT NULL REFERENCES users(id),
  seller_id   uuid NOT NULL REFERENCES users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (listing_id, buyer_id)
);
CREATE TABLE messages (
  id              bigserial PRIMARY KEY,
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id       uuid NOT NULL REFERENCES users(id),
  body            text NOT NULL,
  read_at         timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX messages_thread ON messages (conversation_id, created_at);
CREATE TABLE user_blocks (
  blocker_id uuid REFERENCES users(id) ON DELETE CASCADE,
  blocked_id uuid REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY (blocker_id, blocked_id)
);

-- ANALYTICS, NOTIFICATIONS, REPORTS
CREATE TABLE listing_events (                -- feeds seller analytics
  id         bigserial PRIMARY KEY,
  listing_id bigint NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
  kind       text NOT NULL CHECK (kind IN ('view','enquiry','whatsapp_click','phone_click','favourite','share')),
  user_id    uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX listing_events_rollup ON listing_events (listing_id, kind, created_at);

CREATE TABLE notifications (
  id         bigserial PRIMARY KEY,
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind       text NOT NULL, payload jsonb NOT NULL DEFAULT '{}',
  read_at    timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE reports (
  id           bigserial PRIMARY KEY,
  reporter_id  uuid REFERENCES users(id),
  listing_id   bigint REFERENCES listings(id),
  conversation_id uuid REFERENCES conversations(id),
  reported_user_id uuid REFERENCES users(id),
  reason       report_reason NOT NULL,
  details      text,
  status       report_status NOT NULL DEFAULT 'open',
  handled_by   uuid REFERENCES users(id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  CHECK (listing_id IS NOT NULL OR conversation_id IS NOT NULL OR reported_user_id IS NOT NULL)
);

-- ADMIN-EDITABLE HOMEPAGE CONTENT
CREATE TABLE homepage_blocks (
  id serial PRIMARY KEY, slot text NOT NULL, title text, body jsonb NOT NULL DEFAULT '{}',
  sort_order int NOT NULL DEFAULT 0, is_active boolean NOT NULL DEFAULT true
);

-- NOTES
-- 1. Expiry: a daily job sets status='expired' where expires_at < now(); renewals reset expires_at after a new payment.
-- 2. Never serve exact_point or street_address from public endpoints unless show_exact_address is true.
-- 3. Enable row-level security (or equivalent API checks) so sellers only edit their own listings.
-- 4. Admin stats (revenue, paid listings, enquiries) are queries over payments, listings and listing_events.
