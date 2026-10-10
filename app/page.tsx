import Link from 'next/link';
import { supabaseServer } from '@/lib/supabase';

export const revalidate = 60;
export default async function Home() {
  const { data } = await supabaseServer().from('listings_public').select('slug,title,price_cents,mode').order('published_at', { ascending: false }).limit(12);
  return (
    <main style={{ maxWidth: 900, margin: '0 auto', padding: 24 }}>
      <h1>Khaya Properties</h1>
      <p>Where Property Finds You. Replace this page with the homepage prototype.</p>
      <ul>{(data ?? []).map((l) => (
        <li key={l.slug}><Link href={`/property/${l.slug}`}>{l.title}</Link> from R{Math.round(l.price_cents / 100).toLocaleString('en-ZA')}</li>
      ))}</ul>
    </main>
  );
}
