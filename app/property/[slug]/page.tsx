import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { supabaseServer } from '@/lib/supabase';

// Reads from listings_public, so private addresses can never leak from this page.
async function getListing(slug: string) {
  const { data } = await supabaseServer().from('listings_public').select('*').eq('slug', slug).maybeSingle();
  return data;
}
const rand = (cents: number) => 'R' + Math.round(cents / 100).toLocaleString('en-ZA');

export async function generateMetadata({ params }: { params: { slug: string } }): Promise<Metadata> {
  const l = await getListing(params.slug);
  if (!l) return { title: 'Property not found | Khaya Properties' };
  const desc = l.description.slice(0, 155);
  return {
    title: `${l.title} ${l.mode === 'sale' ? 'for sale' : 'to rent'} ${rand(l.price_cents)} | Khaya Properties`,
    description: desc,
    alternates: { canonical: `/property/${l.slug}` },
    openGraph: { title: l.title, description: desc, type: 'website' },
  };
}

export default async function PropertyPage({ params }: { params: { slug: string } }) {
  const l = await getListing(params.slug);
  if (!l) notFound();
  const ld = { '@context': 'https://schema.org', '@type': 'RealEstateListing', name: l.title, description: l.description,
    offers: { '@type': 'Offer', price: l.price_cents / 100, priceCurrency: 'ZAR' } };
  return (
    <main style={{ maxWidth: 800, margin: '0 auto', padding: 24 }}>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(ld) }} />
      <h1>{l.title}</h1>
      <p><b>{rand(l.price_cents)}</b> {l.mode === 'rent' ? 'per month' : ''}</p>
      <p>{l.description}</p>
      <p style={{ color: '#666' }}>Khaya Properties is a marketplace. This listing is published by an independent advertiser.</p>
      {/* TODO: gallery, features, map (use map_point), seller card, message/WhatsApp buttons, Report listing */}
    </main>
  );
}
