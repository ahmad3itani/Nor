import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'قائمة المتابعة | غولياذور',
  description: 'مباريات الفرق المفضلة القادمة في مكان واحد. لا تفوت أي مباراة لفريقك المحبوب.',
  keywords: ['قائمة متابعة', 'مباريات قادمة', 'فرق مفضلة', 'جدول مباريات'],
  openGraph: {
    title: 'قائمة المتابعة | غولياذور',
    description: 'مباريات فرقك القادمة بلمسة واحدة',
    type: 'website',
    locale: 'ar_SA',
    siteName: 'غولياذور - Goaliador',
  },
  twitter: {
    card: 'summary',
    title: 'قائمة المتابعة | غولياذور',
    description: 'مباريات فرقك القادمة بلمسة واحدة',
  },
};

export default function WatchlistLayout({ children }: { children: React.ReactNode }) {
  return children;
}
