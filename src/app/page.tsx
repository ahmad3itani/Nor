import Link from 'next/link';
import NewsFeed from '@/components/news/NewsFeed';
import MiniMatchesWidget from '@/components/matches/MiniMatchesWidget';
import HomeLeagueStandings from '@/components/home/HomeLeagueStandings';
import HomeTopScorers from '@/components/home/HomeTopScorers';
import HomeFavoritesSection from '@/components/home/HomeFavoritesSection';
import HomeTodaySnapshot from '@/components/home/HomeTodaySnapshot';
import HomeHero from '@/components/home/HomeHero';
import HomeFeaturedMatches from '@/components/home/HomeFeaturedMatches';
import HomeQuickLinks from '@/components/home/HomeQuickLinks';

export const metadata = {
  title: 'غولياذور | منصة كرة القدم الذكية',
  description: 'أخبار كرة القدم، نتائج المباريات الحية، ترتيب الدوريات، إحصائيات اللاعبين والفرق. تغطية شاملة لجميع الدوريات العالمية والعربية بالذكاء الاصطناعي.',
  keywords: ['كرة القدم', 'الدوري الإنجليزي', 'الدوري السعودي', 'نتائج المباريات', 'أخبار الرياضة', 'إحصائيات'],
  openGraph: {
    title: 'غولياذور | منصة كرة القدم الذكية',
    description: 'منصة إعلامية رياضية ذكية - أخبار، نتائج، إحصائيات لحظية لجميع الدوريات',
    type: 'website',
    locale: 'ar_SA',
  },
};

export default function Home() {
  return (
    <div className="space-y-8">

      {/* ── Hero ─────────────────────────────────────────────────────── */}
      <HomeHero />

      {/* ── Quick Navigation ─────────────────────────────────────────── */}
      <HomeQuickLinks />

      {/* ── Quick Stats Strip ────────────────────────────────────────── */}
      <HomeTodaySnapshot />

      {/* ── Today's Featured Matches ─────────────────────────────────── */}
      <HomeFeaturedMatches />

      {/* ── Favorites (only shown when user has saved items) ─────────── */}
      <HomeFavoritesSection />

      {/* ── Divider ──────────────────────────────────────────────────── */}
      <div className="flex items-center gap-4">
        <div className="flex-1 h-px bg-neutral-800" />
        <span className="text-xs font-readex text-neutral-600 shrink-0">آخر الأخبار والإحصائيات</span>
        <div className="flex-1 h-px bg-neutral-800" />
      </div>

      {/* ── Main Grid ────────────────────────────────────────────────── */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">

        {/* Right: News Feed */}
        <div className="lg:col-span-8 space-y-6">
          <div className="flex items-center justify-between">
            <h2 className="text-2xl font-bold font-readex border-r-4 border-nor-green pr-4">آخر الأخبار</h2>
            <Link href="/news" className="flex items-center gap-1 text-sm text-nor-green hover:underline font-readex">
              عرض الكل
              <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="m15 18-6-6 6-6"/></svg>
            </Link>
          </div>
          <NewsFeed />
        </div>

        {/* Left: Sidebar */}
        <aside className="lg:col-span-4 space-y-6">

          {/* Today's matches mini widget */}
          <MiniMatchesWidget />

          {/* League Standings tabs */}
          <HomeLeagueStandings />

          {/* Top Scorers */}
          <HomeTopScorers />

          {/* Quick links hub */}
          <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-5 space-y-3">
            <h3 className="font-readex font-bold text-base flex items-center gap-2">
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="text-nor-green"><path d="M13 2 3 14h9l-1 8 10-12h-9l1-8z"/></svg>
              استكشف المنصة
            </h3>
            <div className="grid grid-cols-2 gap-2">
              {[
                { href: '/compare/players', label: 'مقارنة اللاعبين', icon: '⚖️' },
                { href: '/compare/teams', label: 'مقارنة الفرق', icon: '🏆' },
                { href: '/odds', label: 'الاحتمالات', icon: '📈' },
                { href: '/h2h', label: 'المواجهات', icon: '🤝' },
                { href: '/transfers', label: 'الانتقالات', icon: '🔄' },
                { href: '/injuries', label: 'الإصابات', icon: '🏥' },
              ].map((item) => (
                <Link
                  key={item.href}
                  href={item.href}
                  className="flex items-center gap-2 rounded-xl border border-neutral-800 bg-neutral-800/20 px-3 py-2.5 hover:border-nor-green/30 hover:bg-neutral-800/60 transition-all"
                >
                  <span className="text-base">{item.icon}</span>
                  <span className="text-xs font-readex text-neutral-300">{item.label}</span>
                </Link>
              ))}
            </div>
          </div>

          {/* AI Promo banner */}
          <div className="relative overflow-hidden bg-gradient-to-br from-[#0d1f15] to-[#080808] rounded-2xl p-5 border border-nor-green/20">
            <div className="absolute top-0 left-0 w-40 h-40 bg-nor-green/8 blur-[60px] pointer-events-none" />
            <div className="relative z-10 space-y-3">
              <div className="w-10 h-10 rounded-2xl bg-nor-green/15 border border-nor-green/30 flex items-center justify-center">
                <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#00FF85" strokeWidth="2"><path d="m12 14 4-4"/><path d="M3.34 19a10 10 0 1 1 17.32 0"/></svg>
              </div>
              <div>
                <h3 className="font-readex font-bold text-white text-sm">مدعوم بالذكاء الاصطناعي</h3>
                <p className="text-neutral-500 text-xs font-ibm mt-1 leading-relaxed">
                  أخبار تُعاد كتابتها بالعربية تلقائياً كل 10 دقائق من عشرات المصادر العالمية.
                </p>
              </div>
              <Link
                href="/analytics"
                className="inline-flex items-center gap-1.5 px-4 py-2 bg-nor-green/10 text-nor-green border border-nor-green/30 rounded-full text-xs font-readex hover:bg-nor-green/20 transition-all"
              >
                مركز الإحصائيات
                <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="m15 18-6-6 6-6"/></svg>
              </Link>
            </div>
          </div>

        </aside>
      </div>
    </div>
  );
}
