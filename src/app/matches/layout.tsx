import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'مباريات اليوم | نور',
  description: 'نتائج المباريات الحية وجدول مباريات اليوم وترتيب الفرق. تغطية شاملة لجميع الدوريات.',
  keywords: ['مباريات اليوم', 'نتائج حية', 'ترتيب الدوريات', 'جدول المباريات'],
  openGraph: {
    title: 'مباريات اليوم | نور',
    description: 'نتائج المباريات الحية وترتيب الفرق في جميع الدوريات',
    type: 'website',
    locale: 'ar_SA',
    siteName: 'نور - nōr',
  },
  twitter: {
    card: 'summary',
    title: 'مباريات اليوم | نور',
    description: 'نتائج المباريات الحية وترتيب الفرق في جميع الدوريات',
  },
};

export default function MatchesLayout({ children }: { children: React.ReactNode }) {
  return children;
}
