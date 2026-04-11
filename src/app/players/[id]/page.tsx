import { footballApi, getCurrentSeason } from '@/lib/football-api';
import Link from 'next/link';
import dynamic from 'next/dynamic';
import type { Metadata } from 'next';
import Breadcrumbs from '@/components/ui/Breadcrumbs';

const D3HeatMap = dynamic(() => import('@/components/analytics/D3HeatMap'), { ssr: false, loading: () => <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 h-80 animate-pulse" /> });
const PlayerRatingChart = dynamic(() => import('@/components/analytics/PlayerRatingChart'), { ssr: false, loading: () => <div className="h-64 w-full bg-neutral-800/40 rounded-xl animate-pulse" /> });

export const revalidate = 86400; // 24 hours

export async function generateMetadata({ params }: { params: { id: string } }): Promise<Metadata> {
  try {
    const data = await footballApi.getPlayerStats(params.id, getCurrentSeason());
    if (data?.[0]) {
      const { player, statistics } = data[0];
      return {
        title: `${player.name} | إحصائيات اللاعب - نور`,
        description: `إحصائيات ${player.name} الكاملة: ${statistics[0]?.goals?.total || 0} أهداف، ${statistics[0]?.goals?.assists || 0} تمريرة حاسمة في ${statistics[0]?.league?.name || 'الموسم الحالي'}.`,
        openGraph: { title: `${player.name} | نور`, images: [player.photo], type: 'profile', locale: 'ar_SA' },
      };
    }
  } catch {}
  return { title: 'بيانات اللاعب | نور' };
}

export default async function PlayerProfilePage({ params }: { params: { id: string } }) {
  try {
    const season = getCurrentSeason();
    const [data, trophiesData, transfersData] = await Promise.all([
      footballApi.getPlayerStats(params.id, season),
      footballApi.getPlayerTrophies(params.id).catch(() => []),
      footballApi.getPlayerTransfers(params.id).catch(() => []),
    ]);
    
    if (!data || data.length === 0) {
      return <div className="text-center p-10 text-white font-readex">بيانات اللاعب غير متوفرة</div>;
    }

    const { player, statistics } = data[0];
    const statObj = statistics[0];
    const allLeagueStats = statistics;
    const trophies = trophiesData || [];
    const transfers = transfersData?.[0]?.transfers || [];

    const currentRating = parseFloat(statObj.games.rating) || 7.0;

    // Build real per-league rating data for the chart
    const leagueRatings = allLeagueStats
      .filter((ls: any) => ls.games?.rating && parseFloat(ls.games.rating) > 0)
      .map((ls: any) => ({
        rating: parseFloat(parseFloat(ls.games.rating).toFixed(1)),
        label: ls.league?.name ? ls.league.name.replace('Premier League', 'PL').replace('Champions League', 'UCL').replace('La Liga', 'LaLiga').replace('Serie A', 'Serie A').slice(0, 10) : 'دوري',
      }));

    const ratingHistory = leagueRatings.length >= 2
      ? leagueRatings.map((r: { rating: number }) => r.rating)
      : [currentRating - 0.3, currentRating, currentRating + 0.2, currentRating - 0.1, currentRating]
          .map(r => Math.min(10, Math.max(0, parseFloat(r.toFixed(1)))));

    const chartLabels = leagueRatings.length >= 2
      ? leagueRatings.map((r: { label: string }) => r.label)
      : undefined;
    const totalGoals = allLeagueStats.reduce((sum: number, leagueStat: any) => sum + (leagueStat.goals?.total || 0), 0);
    const totalAssists = allLeagueStats.reduce((sum: number, leagueStat: any) => sum + (leagueStat.goals?.assists || 0), 0);
    const totalMinutes = allLeagueStats.reduce((sum: number, leagueStat: any) => sum + (leagueStat.games?.minutes || 0), 0);
    const titleCount = trophies.filter((t: any) => t.place === 'Winner').length;
    const sectionLinks = [
      { href: '#overview', label: 'نظرة عامة' },
      { href: '#season', label: 'أرقام الموسم' },
      { href: '#performance', label: 'الأداء' },
      { href: '#career', label: 'المسيرة' },
    ];

    const positionAr = (pos: string) => {
      switch (pos) {
        case 'Attacker': return 'مهاجم';
        case 'Midfielder': return 'لاعب وسط';
        case 'Defender': return 'مدافع';
        case 'Goalkeeper': return 'حارس مرمى';
        default: return pos;
      }
    };

    return (
      <div className="max-w-6xl mx-auto space-y-8 pb-20">
         <Breadcrumbs items={[
           { label: 'الإحصائيات', href: '/analytics' },
           { label: player.name },
         ]} />

         {/* Hero Profile */}
         <div id="overview" className="bg-neutral-900 border border-neutral-800 rounded-3xl p-5 sm:p-8 flex flex-col md:flex-row items-center gap-5 sm:gap-8 shadow-2xl relative overflow-hidden">
             <div className="absolute top-0 right-0 w-64 h-64 bg-nor-green/5 blur-3xl pointer-events-none"></div>

             <div className="relative w-24 h-24 sm:w-36 sm:h-36 rounded-full border-4 border-nor-green/30 overflow-hidden bg-neutral-800 shadow-xl shrink-0">
                <img src={player.photo} alt={player.name} className="w-full h-full object-cover" />
             </div>

             <div className="flex-1 text-center md:text-right min-w-0">
                <div className="flex flex-col md:flex-row md:items-center gap-2 sm:gap-4 mb-3 sm:mb-4 justify-center md:justify-start">
                  <h1 className="text-2xl sm:text-3xl md:text-4xl font-bold font-readex tracking-tight">{player.name}</h1>
                  <span className="bg-nor-green/10 text-nor-green border border-nor-green/20 px-3 py-1 rounded-full text-sm font-bold font-ibm shadow-sm w-max mx-auto md:mx-0">
                    {positionAr(statObj.games.position)}
                  </span>
                </div>

                {/* Bio Info Grid */}
                <div className="flex flex-wrap items-center justify-center md:justify-start gap-x-3 sm:gap-x-5 gap-y-1.5 text-neutral-400 font-ibm text-sm mb-4 sm:mb-6">
                   <span>{player.firstname} {player.lastname}</span>
                   <span className="w-1 h-1 rounded-full bg-neutral-600"></span>
                   <span>{player.age} عام ({player.birth?.date})</span>
                   <span className="w-1 h-1 rounded-full bg-neutral-600"></span>
                   <span>{player.nationality}</span>
                   {player.height && <><span className="w-1 h-1 rounded-full bg-neutral-600"></span><span>{player.height}</span></>}
                   {player.weight && <><span className="w-1 h-1 rounded-full bg-neutral-600"></span><span>{player.weight}</span></>}
                </div>

                {statObj.team && (
                  <Link href={`/teams/${statObj.team.id}`} className="flex items-center gap-3 bg-neutral-800/40 hover:bg-neutral-800 transition-all w-max mx-auto md:mx-0 px-5 py-2.5 rounded-2xl border border-neutral-700/50 group backdrop-blur-sm">
                    <img src={statObj.team.logo} className="w-8 h-8 object-contain" alt={statObj.team.name} />
                    <div className="flex flex-col items-start">
                       <span className="text-[10px] text-neutral-500 font-readex uppercase">النادي الحالي</span>
                       <span className="font-readex font-bold group-hover:text-nor-green transition-colors">{statObj.team.name}</span>
                    </div>
                  </Link>
                )}
             </div>
         </div>

         <div className="rounded-3xl border border-neutral-800 bg-neutral-900/80 p-4">
            <div className="flex flex-wrap gap-2">
              {sectionLinks.map((link) => (
                <a
                  key={link.href}
                  href={link.href}
                  className="rounded-full border border-neutral-700 bg-neutral-950 px-4 py-2 text-sm font-readex text-neutral-300 hover:border-nor-green hover:text-nor-green transition-colors"
                >
                  {link.label}
                </a>
              ))}
            </div>
         </div>

         <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
            <div className="rounded-3xl border border-neutral-800 bg-neutral-900 p-5">
              <p className="text-sm text-neutral-500 font-readex">إجمالي الأهداف</p>
              <p className="mt-2 text-3xl font-bold font-readex text-nor-green">{totalGoals}</p>
              <p className="mt-2 text-xs text-neutral-500 font-ibm">في كل البطولات هذا الموسم</p>
            </div>
            <div className="rounded-3xl border border-neutral-800 bg-neutral-900 p-5">
              <p className="text-sm text-neutral-500 font-readex">إجمالي الصناعة</p>
              <p className="mt-2 text-3xl font-bold font-readex text-white">{totalAssists}</p>
              <p className="mt-2 text-xs text-neutral-500 font-ibm">تمريرات حاسمة عبر الموسم</p>
            </div>
            <div className="rounded-3xl border border-neutral-800 bg-neutral-900 p-5">
              <p className="text-sm text-neutral-500 font-readex">الدقائق</p>
              <p className="mt-2 text-3xl font-bold font-readex text-white">{totalMinutes}</p>
              <p className="mt-2 text-xs text-neutral-500 font-ibm">عدد دقائق اللعب الرسمية</p>
            </div>
            <div className="rounded-3xl border border-neutral-800 bg-neutral-900 p-5">
              <p className="text-sm text-neutral-500 font-readex">الألقاب</p>
              <p className="mt-2 text-3xl font-bold font-readex text-yellow-400">{titleCount}</p>
              <p className="mt-2 text-xs text-neutral-500 font-ibm">مرات التتويج المسجلة في البيانات</p>
            </div>
         </div>

         {/* Data Grid */}
         <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
            <div className="lg:col-span-8 flex flex-col gap-8">
               
               {/* Core Stats - Primary League */}
               <div id="season" className="bg-neutral-900 border border-neutral-800 rounded-3xl p-5 sm:p-8 shadow-lg">
                 <h3 className="text-lg sm:text-2xl font-bold font-readex mb-5 sm:mb-8 border-r-4 border-nor-green pr-3 sm:pr-4">أرقام الموسم - {statObj.league.name}</h3>
                 <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                    {[
                      { label: 'مباريات', val: statObj.games.appearences || 0 },
                      { label: 'دقائق', val: statObj.games.minutes || 0 },
                      { label: 'أهداف', val: statObj.goals.total || 0, highlight: true },
                      { label: 'تمريرات حاسمة', val: statObj.goals.assists || 0, highlight: true },
                      { label: 'تسديدات', val: statObj.shots.total || 0 },
                      { label: 'تمريرات رئيسية', val: statObj.passes.key || 0 },
                      { label: 'المراوغات', val: statObj.dribbles.success || 0 },
                      { label: 'التقييم', val: statObj.games.rating ? parseFloat(statObj.games.rating).toFixed(1) : '-', highlight: true }
                    ].map((s, i) => (
                      <div key={i} className={`p-3 sm:p-5 rounded-2xl border ${s.highlight ? 'bg-nor-green/5 border-nor-green/20' : 'bg-neutral-800/20 border-neutral-800/50'} flex flex-col items-center justify-center text-center gap-1`}>
                        <span className={`text-2xl sm:text-3xl font-bold font-ibm ${s.highlight ? 'text-nor-green' : 'text-white'}`}>{s.val}</span>
                        <span className="text-xs text-neutral-500 font-readex">{s.label}</span>
                      </div>
                    ))}
                 </div>
               </div>

               {/* Defensive + Discipline Stats */}
               <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-5 sm:p-8 shadow-lg">
                 <h3 className="text-lg sm:text-2xl font-bold font-readex mb-5 sm:mb-8 border-r-4 border-nor-green pr-3 sm:pr-4">الإحصائيات الدفاعية والانضباط</h3>
                 <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                    {[
                      { label: 'اعتراضات', val: statObj.tackles?.interceptions || 0 },
                      { label: 'تدخلات', val: statObj.tackles?.total || 0 },
                      { label: 'حالات تسلل', val: statObj.offsides || 0 },
                      { label: 'أخطاء مرتكبة', val: statObj.fouls?.committed || 0 },
                      { label: 'أخطاء مكتسبة', val: statObj.fouls?.drawn || 0 },
                      { label: 'بطاقات صفراء', val: statObj.cards?.yellow || 0, warn: true },
                      { label: 'بطاقات حمراء', val: statObj.cards?.red || 0, danger: true },
                      { label: 'مبارزات فاز بها', val: statObj.duels?.won || 0 },
                    ].map((s: any, i) => (
                      <div key={i} className={`p-3 sm:p-5 rounded-2xl border flex flex-col items-center justify-center text-center gap-1 ${
                        s.danger ? 'bg-red-500/5 border-red-500/20' : s.warn ? 'bg-yellow-500/5 border-yellow-500/20' : 'bg-neutral-800/20 border-neutral-800/50'
                      }`}>
                        <span className={`text-2xl sm:text-3xl font-bold font-ibm ${s.danger ? 'text-red-400' : s.warn ? 'text-yellow-400' : 'text-white'}`}>{s.val}</span>
                        <span className="text-xs text-neutral-500 font-readex">{s.label}</span>
                      </div>
                    ))}
                 </div>
               </div>

               {/* All League Stats */}
               {allLeagueStats.length > 1 && (
                 <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-8 shadow-lg">
                   <h3 className="text-lg sm:text-2xl font-bold font-readex mb-5 border-r-4 border-nor-green pr-3 sm:pr-4">إحصائيات كل البطولات</h3>
                   <div className="overflow-x-auto">
                     <table className="w-full text-sm">
                       <thead>
                         <tr className="border-b border-neutral-800 text-neutral-500 font-readex text-xs">
                           <th className="pb-3 text-right">البطولة</th>
                           <th className="pb-3 text-center">لعب</th>
                           <th className="pb-3 text-center">أهداف</th>
                           <th className="pb-3 text-center">تمريرات</th>
                           <th className="pb-3 text-center">تقييم</th>
                         </tr>
                       </thead>
                       <tbody>
                         {allLeagueStats.map((ls: any, idx: number) => (
                           <tr key={idx} className="border-b border-neutral-800/50 hover:bg-neutral-800/20">
                             <td className="py-3 text-right">
                               <div className="flex items-center gap-2">
                                 <img src={ls.league.logo} alt="" className="w-4 h-4 object-contain" />
                                 <span className="font-ibm">{ls.league.name}</span>
                               </div>
                             </td>
                             <td className="py-3 text-center">{ls.games.appearences || 0}</td>
                             <td className="py-3 text-center text-nor-green font-bold">{ls.goals.total || 0}</td>
                             <td className="py-3 text-center">{ls.goals.assists || 0}</td>
                             <td className="py-3 text-center font-bold">{ls.games.rating ? parseFloat(ls.games.rating).toFixed(1) : '-'}</td>
                           </tr>
                         ))}
                       </tbody>
                     </table>
                   </div>
                 </div>
               )}

               {/* Performance Chart */}
               <div id="performance" className="bg-neutral-900 border border-neutral-800 rounded-3xl p-5 sm:p-8 shadow-lg">
                  <h3 className="text-lg sm:text-2xl font-bold font-readex mb-5 sm:mb-8 border-r-4 border-nor-green pr-3 sm:pr-4">منحنى الأداء</h3>
                  <div className="h-64 w-full">
                     <PlayerRatingChart ratings={ratingHistory} labels={chartLabels} />
                  </div>
                  <p className="mt-4 text-center text-xs text-neutral-500 font-ibm">
                     {leagueRatings.length >= 2
                       ? '* يعرض المنحنى التقييم الفعلي لكل بطولة شارك فيها اللاعب هذا الموسم.'
                       : '* يعرض المنحنى تطور التقييم الفني التقديري بناءً على إحصائيات الموسم.'}
                  </p>
               </div>

            </div>

            <div className="lg:col-span-4 flex flex-col gap-8">
              <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 shadow-lg">
                <h4 className="font-readex font-bold mb-4 text-lg">روابط سريعة</h4>
                <div className="space-y-3">
                  {statObj.team ? (
                    <Link href={`/teams/${statObj.team.id}`} className="flex items-center justify-between rounded-2xl border border-neutral-800 bg-neutral-950 px-4 py-3 text-sm font-readex text-neutral-300 hover:border-nor-green hover:text-nor-green transition-colors">
                      <span>ملف النادي الحالي</span>
                      <span>🏟️</span>
                    </Link>
                  ) : null}
                  <Link href="/compare/players" className="flex items-center justify-between rounded-2xl border border-neutral-800 bg-neutral-950 px-4 py-3 text-sm font-readex text-neutral-300 hover:border-nor-green hover:text-nor-green transition-colors">
                    <span>مقارنة مع لاعب آخر</span>
                    <span>🆚</span>
                  </Link>
                  <Link href="/analytics" className="flex items-center justify-between rounded-2xl border border-neutral-800 bg-neutral-950 px-4 py-3 text-sm font-readex text-neutral-300 hover:border-nor-green hover:text-nor-green transition-colors">
                    <span>العودة للإحصائيات</span>
                    <span>📊</span>
                  </Link>
                </div>
              </div>

              <D3HeatMap
                playerPhoto={player.photo}
                position={statObj.games.position}
                intensity={currentRating}
              />
              
              {/* Trophies */}
              {trophies.length > 0 && (
                <div id="career" className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 shadow-lg">
                  <h4 className="font-readex font-bold mb-4 flex items-center gap-2 text-lg">
                    <span className="text-yellow-400">🏆</span> الألقاب والبطولات
                  </h4>
                  <div className="space-y-2 max-h-64 overflow-y-auto hide-scrollbar">
                    {trophies.filter((t: any) => t.place === 'Winner').slice(0, 15).map((trophy: any, idx: number) => (
                      <div key={idx} className="flex items-center gap-3 p-2 rounded-lg bg-neutral-800/30 border border-neutral-800">
                        <span className="text-yellow-400 text-sm">🥇</span>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-ibm font-bold truncate">{trophy.league}</p>
                          <p className="text-xs text-neutral-500">{trophy.season} • {trophy.country}</p>
                        </div>
                      </div>
                    ))}
                    {trophies.filter((t: any) => t.place === 'Winner').length === 0 && (
                      <p className="text-neutral-500 text-sm font-ibm text-center py-4">لم يحصل على ألقاب بعد</p>
                    )}
                  </div>
                </div>
              )}

              {/* Transfer History */}
              {transfers.length > 0 && (
                <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 shadow-lg">
                  <h4 className="font-readex font-bold mb-4 flex items-center gap-2 text-lg">
                    <span>🔄</span> سجل الانتقالات
                  </h4>
                  <div className="space-y-3 max-h-72 overflow-y-auto hide-scrollbar">
                    {transfers.slice(0, 8).map((t: any, idx: number) => (
                      <div key={idx} className="flex items-center gap-3 p-3 rounded-lg bg-neutral-800/30 border border-neutral-800">
                        <div className="flex flex-col items-center gap-1 shrink-0">
                          <img src={t.teams?.out?.logo} alt="" className="w-6 h-6 object-contain" />
                          <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="text-nor-green"><path d="m6 9 6 6 6-6"/></svg>
                          <img src={t.teams?.in?.logo} alt="" className="w-6 h-6 object-contain" />
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="text-xs text-neutral-500 font-readex">{t.date}</p>
                          <p className="text-sm font-ibm"><span className="text-neutral-400">من</span> {t.teams?.out?.name}</p>
                          <p className="text-sm font-ibm"><span className="text-neutral-400">إلى</span> <span className="font-bold text-white">{t.teams?.in?.name}</span></p>
                          {t.type && <p className="text-xs text-neutral-500 mt-1">{t.type}</p>}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* AI Tactical Analysis */}
              <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 shadow-lg">
                 <h4 className="font-readex font-bold mb-4 flex items-center gap-2">
                    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-nor-green"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>
                    تحليل "نور" التكتيكي
                 </h4>
                 <p className="text-neutral-400 text-sm font-ibm leading-relaxed">
                    يعتبر {player.name} من الركائز الأساسية في تشكيلة {statObj.team.name}. يتميز بقدرته العالية على {statObj.games.position === 'Attacker' ? 'إنهاء الهجمات واستغلال الفرص' : statObj.games.position === 'Midfielder' ? 'التحكم في ريتم اللعب وإرسال التمريرات المفتاحية' : statObj.games.position === 'Goalkeeper' ? 'التصدي والتوزيع من الخلف' : 'التغطية الدفاعية وقطع الكرات'}. 
                    تقييمه الحالي ({statObj.games.rating ? parseFloat(statObj.games.rating).toFixed(1) : '-'}) يضعه ضمن نخبة لاعبي {statObj.league.name}.
                 </p>
              </div>
            </div>
         </div>

      </div>
    );
  } catch (error) {
    console.error('Player Hub Error:', error);
    return <div className="text-center p-10 font-readex text-red-500">حدث خطأ أثناء جلب بيانات اللاعب</div>;
  }
}
