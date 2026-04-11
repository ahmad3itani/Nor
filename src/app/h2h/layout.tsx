import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'المواجهات المباشرة | نور',
  description: 'قارن بين أي فريقين وشاهد السجل التاريخي الكامل لمواجهاتهما المباشرة. نتائج، أهداف، وإحصائيات.',
  keywords: ['مواجهات مباشرة', 'head to head', 'سجل تاريخي', 'مقارنة فرق'],
  openGraph: {
    title: 'المواجهات المباشرة | نور',
    description: 'السجل التاريخي الكامل بين أي فريقين',
    type: 'website',
    locale: 'ar_SA',
    siteName: 'نور - nōr',
  },
  twitter: {
    card: 'summary',
    title: 'المواجهات المباشرة | نور',
    description: 'السجل التاريخي الكامل بين أي فريقين',
  },
};

export default function H2HLayout({ children }: { children: React.ReactNode }) {
  return children;
}
