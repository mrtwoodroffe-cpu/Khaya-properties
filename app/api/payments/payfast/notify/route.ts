import { supabaseAdmin } from '@/lib/supabase';
import { verifyItn } from '@/lib/payfast';

// PayFast calls this after payment. A listing only goes live from here, never from the browser.
export async function POST(req: Request) {
  const raw = await req.text();
  if (!(await verifyItn(raw))) return new Response('invalid', { status: 400 });

  const p = new URLSearchParams(raw);
  const db = supabaseAdmin();
  const { data: pay } = await db.from('payments').select('*').eq('id', p.get('m_payment_id')).single();
  if (!pay) return new Response('unknown payment', { status: 404 });

  // The amount must match what we charged (price snapshot), not what the request claims
  if (Math.round(parseFloat(p.get('amount_gross') ?? '0') * 100) !== pay.amount_cents) return new Response('amount mismatch', { status: 400 });

  const status = p.get('payment_status');
  if (status === 'COMPLETE') {
    const { error } = await db.rpc('activate_listing_payment', { p_payment_id: pay.id, p_gateway_ref: p.get('pf_payment_id') });
    if (error) return new Response('activation failed', { status: 500 }); // PayFast retries
  } else if (status === 'FAILED' || status === 'CANCELLED') {
    await db.from('payments').update({ status: 'failed' }).eq('id', pay.id).neq('status', 'paid');
  }
  return new Response('ok');
}
