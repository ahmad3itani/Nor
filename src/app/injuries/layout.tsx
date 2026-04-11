import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'تقرير الإصابات والإيقافات | نور',
  description: 'قائمة محدثة بأحدث إصابات اللاعبين وإيقافاتهم في جميع الدوريات. حالة اللاعبين ومواعيد العودة المتوقعة.',
  keywords: ['إصابات اللاعبين', 'إيقافات', 'موعد العودة', 'تقرير طبي', 'غياب اللاعبين'],
  openGraph: {
    title: 'تقرير الإصابات والإيقافات | نور',
    description: 'آخر تحديثات إصابات اللاعبين في جميع الدوريات',
    type: 'website',
    locale: 'ar_SA',
    siteName: 'نور - nōr',
  },
  twitter: {
    card: 'summary',
    title: 'تقرير الإصابات والإيقافات | نور',
    description: 'آخر تحديثات إصابات اللاعبين في جميع الدوريات',
  },
};

export default function InjuriesLayout({ children }: { children: React.ReactNode }) {
  return children;
}
