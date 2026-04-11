import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'مفضلاتي | نور',
  description: 'دوريات وفرق كرة القدم المفضلة لديك. وصول سريع لمتابعة آخر أخبار فرقك وبطولاتك.',
  keywords: ['مفضلة', 'فرقي', 'دورياتي', 'متابعة الفرق'],
  openGraph: {
    title: 'مفضلاتي | نور',
    description: 'فرقك وبطولاتك المفضلة في مكان واحد',
    type: 'website',
    locale: 'ar_SA',
    siteName: 'نور - nōr',
  },
  twitter: {
    card: 'summary',
    title: 'مفضلاتي | نور',
    description: 'فرقك وبطولاتك المفضلة في مكان واحد',
  },
};

export default function FavoritesLayout({ children }: { children: React.ReactNode }) {
  return children;
}
