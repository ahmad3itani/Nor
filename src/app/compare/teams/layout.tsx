import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'مقارنة الفرق الموسمية | نور',
  description: 'قارن بين أي فريقين في مؤشرات الموسم: الانتصارات، الأهداف، الترتيب، والمواجهات المباشرة.',
  keywords: ['مقارنة فرق', 'إحصائيات الموسم', 'أفضل فريق', 'تحليل الفرق'],
  openGraph: {
    title: 'مقارنة الفرق الموسمية | نور',
    description: 'مؤشرات موسمية مقارنة بين فريقين من أي دوري',
    type: 'website',
    locale: 'ar_SA',
    siteName: 'نور - nōr',
  },
  twitter: {
    card: 'summary',
    title: 'مقارنة الفرق الموسمية | نور',
    description: 'مؤشرات موسمية مقارنة بين فريقين من أي دوري',
  },
};

export default function CompareTeamsLayout({ children }: { children: React.ReactNode }) {
  return children;
}
