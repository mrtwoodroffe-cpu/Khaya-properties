import { supabaseServer } from '@/lib/supabase';

const slugify = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

// Creates a draft listing. Photos upload to storage separately; payment then moves it forward.
export async function POST(req: Request) {
  const sb = supabaseServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return Response.json({ error: 'Sign in first' }, { status: 401 });
  const b = await req.json();
  if (!b.title || !b.description || !(b.priceCents > 0)) return Response.json({ error: 'Title, description and price are required' }, { status: 400 });

  const [{ data: cat }, { data: loc }] = await Promise.all([
    sb.from('categories').select('name').eq('id', b.categoryId).single(),
    sb.from('locations').select('name').eq('id', b.locationId).single(),
  ]);
  if (!cat || !loc) return Response.json({ error: 'Invalid category or location' }, { status: 400 });

  const { data, error } = await sb.from('listings').insert({
    owner_id: user.id, seller_type: b.sellerType, mode: b.mode, category_id: b.categoryId, location_id: b.locationId,
    title: b.title, description: b.description, price_cents: b.priceCents, bedrooms: b.bedrooms, bathrooms: b.bathrooms, parking: b.parking,
    floor_size_m2: b.floorSize, land_size_m2: b.landSize, street_address: b.address, show_exact_address: !!b.showExactAddress,
    slug: crypto.randomUUID(), status: 'draft',
  }).select('id').single();
  if (error || !data) return Response.json({ error: 'Could not save listing' }, { status: 500 });

  const slug = slugify(`${b.bedrooms ?? ''} bedroom ${cat.name} ${loc.name}`) + `-${data.id}`;
  await sb.from('listings').update({ slug }).eq('id', data.id);
  return Response.json({ id: data.id, slug });
}
