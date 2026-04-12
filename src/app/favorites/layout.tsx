import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'مفضلاتي | غولياذور',
  description: 'دوريات وفرق كرة القدم المفضلة لديك. وصول سريع لمتابعة آخر أخبار فرقك وبطولاتك.',
  keywords: ['مفضلة', 'فرقي', 'دورياتي', 'متابعة الفرق'],
  openGraph: {
    title: 'مفضلاتي | غولياذور',
    description: 'فرقك وبطولاتك المفضلة في مكان واحد',
    type: 'website',
    locale: 'ar_SA',
    siteName: 'غولياذور - Goaliador',
  },
  twitter: {
    card: 'summary',
    title: 'مفضلاتي | غولياذور',
    description: 'فرقك وبطولاتك المفضلة في مكان واحد',
  },
};

export default function FavoritesLayout({ children }: { children: React.ReactNode }) {
  return children;
}
