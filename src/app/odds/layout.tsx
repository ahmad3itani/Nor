import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'احتمالات المباريات | غولياذور',
  description: 'احتمالات الفوز والتعادل والخسارة من أكبر شركات المراهنات. قارن الاحتمالات قبل كل مباراة.',
  keywords: ['احتمالات مباريات', 'أوزان الفوز', 'توقعات كرة القدم', 'نسب الفوز'],
  openGraph: {
    title: 'احتمالات المباريات | غولياذور',
    description: 'أفضل احتمالات الفوز والتعادل من شركات المراهنات',
    type: 'website',
    locale: 'ar_SA',
    siteName: 'غولياذور - Goaliador',
  },
  twitter: {
    card: 'summary',
    title: 'احتمالات المباريات | غولياذور',
    description: 'أفضل احتمالات الفوز والتعادل من شركات المراهنات',
  },
};

export default function OddsLayout({ children }: { children: React.ReactNode }) {
  return children;
}
