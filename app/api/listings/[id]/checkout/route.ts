import { supabaseServer, supabaseAdmin } from '@/lib/supabase';
import { checkoutFields, PROCESS_URL } from '@/lib/payfast';

// Starts payment. The price comes from the packages table, never from the client.
export async function POST(req: Request, { params }: { params: { id: string } }) {
  const sb = supabaseServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return Response.json({ error: 'Sign in first' }, { status: 401 });

  const { packageId } = await req.json();
  const { data: listing } = await sb.from('listings').select('id,status,owner_id').eq('id', params.id).single();
  if (!listing || listing.owner_id !== user.id) return Response.json({ error: 'Not found' }, { status: 404 });
  if (!['draft', 'payment_pending', 'expired'].includes(listing.status)) return Response.json({ error: 'Listing cannot be paid for now' }, { status: 409 });

  const db = supabaseAdmin();
  const { data: pkg } = await db.from('packages').select('*').eq('id', packageId).eq('is_active', true).single();
  if (!pkg) return Response.json({ error: 'Unknown package' }, { status: 400 });

  const { data: pay, error } = await db.from('payments').insert({
    user_id: user.id, listing_id: listing.id, package_id: pkg.id, amount_cents: pkg.price_cents, gateway: 'payfast', status: 'pending',
  }).select('id').single();
  if (error || !pay) return Response.json({ error: 'Could not start payment' }, { status: 500 });

  await db.from('listings').update({ status: 'payment_pending', package_id: pkg.id }).eq('id', listing.id);
  const fields = checkoutFields({
    paymentId: pay.id, amountCents: pkg.price_cents, itemName: `Khaya listing: ${pkg.name}`,
    email: user.email!, firstName: (user.user_metadata?.full_name ?? 'Seller').split(' ')[0],
  });
  return Response.json({ action: PROCESS_URL, fields }); // browser posts these fields to PayFast
}
