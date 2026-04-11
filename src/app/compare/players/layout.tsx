import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'مقارنة اللاعبين | نور',
  description: 'قارن بين أي لاعبين في الأداء، الأهداف، التمريرات، والتقييمات. تحليل إحصائي مرئي بالرادار.',
  keywords: ['مقارنة لاعبين', 'إحصائيات لاعبين', 'أفضل لاعب', 'رادار الأداء'],
  openGraph: {
    title: 'مقارنة اللاعبين | نور',
    description: 'تحليل مقارن إحصائي بين لاعبين من أي دوري',
    type: 'website',
    locale: 'ar_SA',
    siteName: 'نور - nōr',
  },
  twitter: {
    card: 'summary',
    title: 'مقارنة اللاعبين | نور',
    description: 'تحليل مقارن إحصائي بين لاعبين من أي دوري',
  },
};

export default function ComparePlayersLayout({ children }: { children: React.ReactNode }) {
  return children;
}
