import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'تنبيهات المباريات | نور',
  description: 'اضبط تنبيهات لمباريات فرقك المفضلة ولا تفوت أي انطلاقة. إشعارات مباشرة على متصفحك.',
  keywords: ['تنبيهات مباريات', 'إشعارات', 'تذكير مباراة', 'مواعيد المباريات'],
  openGraph: {
    title: 'تنبيهات المباريات | نور',
    description: 'تنبيهات فورية قبل انطلاق مباريات فرقك',
    type: 'website',
    locale: 'ar_SA',
    siteName: 'نور - nōr',
  },
  twitter: {
    card: 'summary',
    title: 'تنبيهات المباريات | نور',
    description: 'تنبيهات فورية قبل انطلاق مباريات فرقك',
  },
};

export default function RemindersLayout({ children }: { children: React.ReactNode }) {
  return children;
}
