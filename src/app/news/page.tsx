import NewsFeed from '@/components/news/NewsFeed';
import Breadcrumbs from '@/components/ui/Breadcrumbs';
import MostRead from '@/components/news/MostRead';

export const metadata = {
  title: 'آخر أخبار كرة القدم العاجلة اليوم | نور',
  description: 'اقرأ أحدث أخبار كرة القدم العاجلة اليوم: انتقالات اللاعبين، نتائج المباريات، إصابات النجوم، وتحليلات تكتيكية حصرية. تغطية شاملة للدوريات العالمية والعربية بالذكاء الاصطناعي.',
  keywords: [
    'أخبار كرة القدم اليوم', 'أخبار عاجلة رياضية', 'انتقالات اللاعبين', 'أخبار ريال مدريد',
    'أخبار برشلونة', 'أخبار مانشستر سيتي', 'أخبار الدوري السعودي', 'أخبار دوري الأبطال',
    'أحداث كرة القدم', 'نقلات الميركاتو', 'إصابات اللاعبين', 'تحليلات تكتيكية',
  ],
  openGraph: {
    title: 'أخبار كرة القدم العاجلة اليوم | نور',
    description: 'آخر الأخبار الرياضية: انتقالات، نتائج، إصابات، وتحليلات لحظية بالذكاء الاصطناعي.',
    type: 'website',
    locale: 'ar_SA',
    siteName: 'نور - nōr',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'أخبار كرة القدم العاجلة | نور',
    description: 'تغطية إخبارية شاملة لكرة القدم العالمية والعربية.',
  },
};

export default function NewsPage() {
  return (
    <div className="max-w-6xl mx-auto space-y-6">
      <Breadcrumbs items={[{ label: 'الأخبار' }]} />
      <div className="space-y-3">
        <div className="inline-flex items-center gap-2 px-3 py-1 bg-nor-green/10 border border-nor-green/20 rounded-full text-nor-green text-xs font-readex">
          <span className="w-1.5 h-1.5 rounded-full bg-nor-green animate-pulse" />
          تحديث مستمر بالذكاء الاصطناعي
        </div>
        <h1 className="text-2xl sm:text-3xl md:text-4xl font-bold font-readex text-white">
          أخبار كرة القدم العاجلة <span className="text-nor-green">اليوم</span>
        </h1>
        <p className="text-neutral-400 font-ibm text-sm sm:text-base max-w-2xl">
          انتقالات اللاعبين، نتائج المباريات، إصابات النجوم، وتحليلات تكتيكية — تُكتب بالعربية تلقائياً من أبرز المصادر العالمية
        </p>
      </div>

      <div className="grid gap-8 lg:grid-cols-[1fr_300px]">
        <NewsFeed />
        <aside className="space-y-6">
          <MostRead />
        </aside>
      </div>
    </div>
  );
}
