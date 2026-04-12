import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'سوق الانتقالات | غولياذور',
  description: 'آخر أخبار انتقالات اللاعبين والصفقات المؤكدة. تتبع القادمين والمغادرين لكل نادٍ في جميع الدوريات.',
  keywords: ['انتقالات اللاعبين', 'صفقات كرة القدم', 'سوق الانتقالات', 'ميركاتو'],
  openGraph: {
    title: 'سوق الانتقالات | غولياذور',
    description: 'أحدث صفقات الانتقالات والقادمين والمغادرين',
    type: 'website',
    locale: 'ar_SA',
    siteName: 'غولياذور - Goaliador',
  },
  twitter: {
    card: 'summary',
    title: 'سوق الانتقالات | غولياذور',
    description: 'أحدث صفقات الانتقالات والقادمين والمغادرين',
  },
};

export default function TransfersLayout({ children }: { children: React.ReactNode }) {
  return children;
}
