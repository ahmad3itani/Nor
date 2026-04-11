import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'قائمة المتابعة | نور',
  description: 'مباريات الفرق المفضلة القادمة في مكان واحد. لا تفوت أي مباراة لفريقك المحبوب.',
  keywords: ['قائمة متابعة', 'مباريات قادمة', 'فرق مفضلة', 'جدول مباريات'],
  openGraph: {
    title: 'قائمة المتابعة | نور',
    description: 'مباريات فرقك القادمة بلمسة واحدة',
    type: 'website',
    locale: 'ar_SA',
    siteName: 'نور - nōr',
  },
  twitter: {
    card: 'summary',
    title: 'قائمة المتابعة | نور',
    description: 'مباريات فرقك القادمة بلمسة واحدة',
  },
};

export default function WatchlistLayout({ children }: { children: React.ReactNode }) {
  return children;
}
