import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'تنبيهات المباريات | غولياذور',
  description: 'اضبط تنبيهات لمباريات فرقك المفضلة ولا تفوت أي انطلاقة. إشعارات مباشرة على متصفحك.',
  keywords: ['تنبيهات مباريات', 'إشعارات', 'تذكير مباراة', 'مواعيد المباريات'],
  openGraph: {
    title: 'تنبيهات المباريات | غولياذور',
    description: 'تنبيهات فورية قبل انطلاق مباريات فرقك',
    type: 'website',
    locale: 'ar_SA',
    siteName: 'غولياذور - Goaliador',
  },
  twitter: {
    card: 'summary',
    title: 'تنبيهات المباريات | غولياذور',
    description: 'تنبيهات فورية قبل انطلاق مباريات فرقك',
  },
};

export default function RemindersLayout({ children }: { children: React.ReactNode }) {
  return children;
}
