import { supabaseAdmin } from '@/lib/supabase';

// Daily job (see vercel.json). Vercel sends: Authorization: Bearer $CRON_SECRET
export async function GET(req: Request) {
  if (req.headers.get('authorization') !== `Bearer ${process.env.CRON_SECRET}`) return new Response('forbidden', { status: 403 });
  const { data, error } = await supabaseAdmin().rpc('expire_listings');
  return error ? new Response('error', { status: 500 }) : Response.json({ expired: data });
}
