import type { Metadata, Viewport } from 'next';
import './globals.css';
export const metadata: Metadata = {
  metadataBase: new URL('https://bilfred.com'),
  title: 'Bilfred — Bilvedlikehold på cruisekontroll',
  description: 'EU-kontroll, service og vedlikehold. Samlet i én app. Meld deg på for tidlig tilgang til Bilfred.',
  alternates: { canonical: '/' },
  openGraph: { title: 'Bilfred', description: 'Bilvedlikehold på cruisekontroll.', locale: 'nb_NO', type: 'website', url: 'https://bilfred.com' },
};
export const viewport: Viewport = { themeColor: '#08070c', width: 'device-width', initialScale: 1 };
export default function Layout({ children }: Readonly<{ children: React.ReactNode }>) { return <html lang="nb"><body>{children}</body></html>; }
