import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'سوق الانتقالات | نور',
  description: 'آخر أخبار انتقالات اللاعبين والصفقات المؤكدة. تتبع القادمين والمغادرين لكل نادٍ في جميع الدوريات.',
  keywords: ['انتقالات اللاعبين', 'صفقات كرة القدم', 'سوق الانتقالات', 'ميركاتو'],
  openGraph: {
    title: 'سوق الانتقالات | نور',
    description: 'أحدث صفقات الانتقالات والقادمين والمغادرين',
    type: 'website',
    locale: 'ar_SA',
    siteName: 'نور - nōr',
  },
  twitter: {
    card: 'summary',
    title: 'سوق الانتقالات | نور',
    description: 'أحدث صفقات الانتقالات والقادمين والمغادرين',
  },
};

export default function TransfersLayout({ children }: { children: React.ReactNode }) {
  return children;
}
