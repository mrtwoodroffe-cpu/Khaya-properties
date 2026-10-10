import crypto from 'crypto';

const HOST = process.env.PAYFAST_SANDBOX === 'true' ? 'https://sandbox.payfast.co.za' : 'https://www.payfast.co.za';
export const PROCESS_URL = `${HOST}/eng/process`;
const VALIDATE_URL = `${HOST}/eng/query/validate`;

// PayFast expects PHP-style urlencode: spaces as +, uppercase hex, and !'()* encoded
const enc = (v: string) =>
  encodeURIComponent(v.trim()).replace(/[!'()*]/g, (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase()).replace(/%20/g, '+');

export function sign(pairs: [string, string][]) {
  let qs = pairs.filter(([, v]) => v !== '').map(([k, v]) => `${k}=${enc(v)}`).join('&');
  if (process.env.PAYFAST_PASSPHRASE) qs += `&passphrase=${enc(process.env.PAYFAST_PASSPHRASE)}`;
  return crypto.createHash('md5').update(qs).digest('hex');
}

// Field order matters: it must match the order the form posts them in.
export function checkoutFields(o: { paymentId: string; amountCents: number; itemName: string; email: string; firstName: string }) {
  const site = process.env.NEXT_PUBLIC_SITE_URL!;
  const pairs: [string, string][] = [
    ['merchant_id', process.env.PAYFAST_MERCHANT_ID!],
    ['merchant_key', process.env.PAYFAST_MERCHANT_KEY!],
    ['return_url', `${site}/dashboard?paid=1`],
    ['cancel_url', `${site}/dashboard?cancelled=1`],
    ['notify_url', `${site}/api/payments/payfast/notify`],
    ['name_first', o.firstName],
    ['email_address', o.email],
    ['m_payment_id', o.paymentId],
    ['amount', (o.amountCents / 100).toFixed(2)],
    ['item_name', o.itemName],
  ];
  return [...pairs, ['signature', sign(pairs)] as [string, string]];
}

// Verifies an Instant Transaction Notification: signature, then PayFast's own server-side check.
export async function verifyItn(raw: string) {
  const pairs = [...new URLSearchParams(raw).entries()].filter(([k]) => k !== 'signature');
  const given = new URLSearchParams(raw).get('signature');
  if (!given || sign(pairs) !== given) return false;
  const body = pairs.map(([k, v]) => `${k}=${enc(v)}`).join('&');
  const r = await fetch(VALIDATE_URL, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body });
  return (await r.text()).trim() === 'VALID';
}
