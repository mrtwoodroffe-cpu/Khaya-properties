-- Create a profile row whenever someone signs up
create function handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into users (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

create function is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from users where id = auth.uid() and role in ('admin','moderator'));
$$;

-- Public read model: never exposes street_address or exact_point
create view listings_public as
  select id, slug, owner_id, seller_type, mode, category_id, location_id, title, description, price_cents,
         previous_price_cents, bedrooms, bathrooms, parking, floor_size_m2, land_size_m2, rates_cents, levies_cents,
         furnished, pet_friendly, is_new_development, video_url, virtual_tour_url,
         case when show_exact_address then street_address end as street_address,
         case when show_exact_address then exact_point else public_point end as map_point,
         package_id, featured_until, published_at, expires_at, views_count
  from listings where status = 'active';
grant select on listings_public to anon, authenticated;

-- Row level security
alter table users enable row level security;
alter table listings enable row level security;
alter table listing_media enable row level security;
alter table favourites enable row level security;
alter table saved_searches enable row level security;
alter table conversations enable row level security;
alter table messages enable row level security;
alter table payments enable row level security;
alter table reports enable row level security;

create policy users_self on users for select using (id = auth.uid() or is_admin());
create policy users_update_self on users for update using (id = auth.uid()) with check (id = auth.uid() and role = 'user');

-- Owners read/edit their own listings but cannot self-activate. Activation, resume and renewal go through server routes.
create policy listings_owner_read on listings for select using (owner_id = auth.uid() or is_admin());
create policy listings_owner_insert on listings for insert with check (owner_id = auth.uid() and status = 'draft');
create policy listings_owner_update on listings for update using (owner_id = auth.uid())
  with check (owner_id = auth.uid() and status in ('draft','payment_pending','paused'));
create policy listings_admin_all on listings for all using (is_admin()) with check (is_admin());

create policy media_owner on listing_media for all
  using (exists (select 1 from listings l where l.id = listing_id and l.owner_id = auth.uid()))
  with check (exists (select 1 from listings l where l.id = listing_id and l.owner_id = auth.uid()));
create policy media_public_read on listing_media for select
  using (exists (select 1 from listings l where l.id = listing_id and l.status = 'active'));

create policy fav_self on favourites for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy ss_self on saved_searches for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy conv_party on conversations for select using (buyer_id = auth.uid() or seller_id = auth.uid() or is_admin());
create policy conv_start on conversations for insert with check (buyer_id = auth.uid());
create policy msg_party on messages for select using (exists (select 1 from conversations c where c.id = conversation_id and (c.buyer_id = auth.uid() or c.seller_id = auth.uid())) or is_admin());
create policy msg_send on messages for insert with check (sender_id = auth.uid() and exists (select 1 from conversations c where c.id = conversation_id and (c.buyer_id = auth.uid() or c.seller_id = auth.uid())));
create policy pay_owner on payments for select using (user_id = auth.uid() or is_admin());
create policy rep_create on reports for insert with check (reporter_id = auth.uid());
create policy rep_admin on reports for select using (is_admin());

-- Atomic activation, called only by the verified payment webhook (service role)
create function activate_listing_payment(p_payment_id uuid, p_gateway_ref text) returns void
language plpgsql security definer set search_path = public as $$
declare pay payments; pkg packages; auto boolean; new_status listing_status;
begin
  select * into pay from payments where id = p_payment_id for update;
  if not found or pay.status = 'paid' then return; end if;   -- idempotent
  select * into pkg from packages where id = pay.package_id;
  select coalesce((value)::text::boolean, false) into auto from settings where key = 'auto_approve';
  new_status := case when coalesce(auto,false) then 'active' else 'pending_review' end;
  update payments set status = 'paid', paid_at = now(), gateway_ref = p_gateway_ref where id = pay.id;
  update listings set status = new_status,
         package_id = pkg.id,
         published_at = case when new_status = 'active' then now() else published_at end,
         expires_at = now() + make_interval(days => pkg.duration_days),
         featured_until = case when pkg.is_featured then now() + make_interval(days => pkg.duration_days) end
   where id = pay.listing_id;
  insert into moderation_events (listing_id, to_status, note) values (pay.listing_id, new_status, 'Payment confirmed');
end $$;
revoke all on function activate_listing_payment from public, anon, authenticated;

create function expire_listings() returns int language sql security definer set search_path = public as $$
  with u as (update listings set status = 'expired' where status = 'active' and expires_at < now() returning 1)
  select count(*)::int from u;
$$;
revoke all on function expire_listings from public, anon, authenticated;
