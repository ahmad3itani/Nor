import TopScorersTable from '@/components/analytics/TopScorersTable';
import TopAssistsTable from '@/components/analytics/TopAssistsTable';
import LeagueSwitcher from '@/components/ui/LeagueSwitcher';
import AnalyticsCardsSection from '@/components/analytics/AnalyticsCardsSection';
import AnalyticsStandingsSnapshot from '@/components/analytics/AnalyticsStandingsSnapshot';
import { getLeagueMap } from '@/lib/config/leagues';
import Link from 'next/link';
import Breadcrumbs from '@/components/ui/Breadcrumbs';

export const metadata = {
  title: 'إحصائيات كرة القدم | هدافون، ترتيب الدوريات، ومقارنات اللاعبين | غولياذور',
  description: 'إحصائيات كرة القدم الشاملة: الهدافون، صناع اللعب، ترتيب الدوريات، مقارنة اللاعبين والفرق، والبطاقات. بيانات محدثة لحظياً من البريميرليغ، لاليغا، دوري الأبطال، والدوري السعودي.',
  keywords: [
    'إحصائيات كرة القدم', 'هدافون البريميرليغ', 'ترتيب الدوري الإنجليزي',
    'مقارنة اللاعبين', 'أفضل هداف', 'صناع اللعب', 'إحصائيات اللاعبين',
    'ترتيب لاليغا', 'إحصائيات دوري الأبطال', 'تحليل الأداء',
  ],
  openGraph: {
    title: 'إحصائيات كرة القدم الشاملة | غولياذور',
    description: 'هدافون، ترتيب الدوريات، ومقارنة اللاعبين — بيانات محدثة لحظياً.',
    type: 'website',
    locale: 'ar_SA',
    siteName: 'غولياذور - Goaliador',
  },
  twitter: {
    card: 'summary',
    title: 'إحصائيات كرة القدم | غولياذور',
    description: 'هدافون وترتيب الدوريات ومقارنات اللاعبين لحظياً.',
  },
};

export default function AnalyticsPage({ searchParams }: { searchParams: { league?: string } }) {
  const leagueId = searchParams.league || '39';
  const leagueData = getLeagueMap(leagueId);

  return (
    <div className="max-w-7xl mx-auto space-y-10">
      <Breadcrumbs items={[{ label: 'مركز الإحصائيات' }]} />
      {/* Hero Header */}
      <div className="text-center space-y-4">
        <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-nor-green/10 border border-nor-green/20 rounded-full text-nor-green text-sm font-readex">
          <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M3 3v18h18"/><path d="m19 9-5 5-4-4-3 3"/></svg>
          بيانات محدثة لحظياً
        </div>
        <h1 className="text-2xl sm:text-3xl md:text-4xl font-bold font-readex text-white">مركز الإحصائيات الشامل</h1>
        <p className="text-neutral-400 font-ibm text-sm sm:text-base max-w-2xl mx-auto">أرقام وإحصائيات <span className="text-nor-green font-bold">{leagueData.name}</span> - الهدافون، صناع اللعب، البطاقات، والترتيب</p>
      </div>

      <LeagueSwitcher />

      {/* Summary Cards */}
      <AnalyticsCardsSection leagueId={leagueId} />

      {/* Main Stats Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
        {/* Top Scorers */}
        <div className="lg:col-span-6 bg-neutral-900 border border-neutral-800 rounded-3xl p-6">
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-xl font-bold font-readex border-r-4 border-nor-green pr-3">الهدافون</h2>
            <span className="text-xs text-neutral-500 font-readex bg-neutral-800/50 px-3 py-1 rounded-full">{leagueData.name}</span>
          </div>
          <TopScorersTable leagueId={leagueId} />
        </div>

        {/* Top Assists */}
        <div className="lg:col-span-6 bg-neutral-900 border border-neutral-800 rounded-3xl p-6">
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-xl font-bold font-readex border-r-4 border-nor-green pr-3">صناع اللعب</h2>
            <span className="text-xs text-neutral-500 font-readex bg-neutral-800/50 px-3 py-1 rounded-full">{leagueData.name}</span>
          </div>
          <TopAssistsTable leagueId={leagueId} />
        </div>
      </div>

      {/* Standings Snapshot */}
      <AnalyticsStandingsSnapshot leagueId={leagueId} leagueName={leagueData.name} />

      {/* Quick Links */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
        <Link href="/compare/players" className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6 hover:border-nor-green/50 transition-all group text-center">
          <span className="text-3xl block mb-3">🆚</span>
          <h3 className="font-readex font-bold text-white group-hover:text-nor-green transition-colors">مقارنة اللاعبين</h3>
          <p className="text-xs text-neutral-500 font-ibm mt-1">قارن أي لاعبين بالأرقام</p>
        </Link>
        <Link href="/compare/teams" className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6 hover:border-nor-green/50 transition-all group text-center">
          <span className="text-3xl block mb-3">🛡️</span>
          <h3 className="font-readex font-bold text-white group-hover:text-nor-green transition-colors">مقارنة الفرق</h3>
          <p className="text-xs text-neutral-500 font-ibm mt-1">ترتيب، نقاط، هجوم ودفاع</p>
        </Link>
        <Link href="/h2h" className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6 hover:border-nor-green/50 transition-all group text-center">
          <span className="text-3xl block mb-3">⚔️</span>
          <h3 className="font-readex font-bold text-white group-hover:text-nor-green transition-colors">سجل المواجهات</h3>
          <p className="text-xs text-neutral-500 font-ibm mt-1">تاريخ اللقاءات المباشرة</p>
        </Link>
        <Link href="/injuries" className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6 hover:border-nor-green/50 transition-all group text-center">
          <span className="text-3xl block mb-3">🏥</span>
          <h3 className="font-readex font-bold text-white group-hover:text-nor-green transition-colors">تقرير الإصابات</h3>
          <p className="text-xs text-neutral-500 font-ibm mt-1">اللاعبون المصابون</p>
        </Link>
        <Link href="/transfers" className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6 hover:border-nor-green/50 transition-all group text-center">
          <span className="text-3xl block mb-3">🔄</span>
          <h3 className="font-readex font-bold text-white group-hover:text-nor-green transition-colors">سوق الانتقالات</h3>
          <p className="text-xs text-neutral-500 font-ibm mt-1">أحدث الصفقات</p>
        </Link>
      </div>
    </div>
  );
}
