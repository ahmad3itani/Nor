import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'احتمالات المباريات | نور',
  description: 'احتمالات الفوز والتعادل والخسارة من أكبر شركات المراهنات. قارن الاحتمالات قبل كل مباراة.',
  keywords: ['احتمالات مباريات', 'أوزان الفوز', 'توقعات كرة القدم', 'نسب الفوز'],
  openGraph: {
    title: 'احتمالات المباريات | نور',
    description: 'أفضل احتمالات الفوز والتعادل من شركات المراهنات',
    type: 'website',
    locale: 'ar_SA',
    siteName: 'نور - nōr',
  },
  twitter: {
    card: 'summary',
    title: 'احتمالات المباريات | نور',
    description: 'أفضل احتمالات الفوز والتعادل من شركات المراهنات',
  },
};

export default function OddsLayout({ children }: { children: React.ReactNode }) {
  return children;
}
