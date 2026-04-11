import { footballApi, getCurrentSeason } from '@/lib/football-api';
import Link from 'next/link';
import type { Metadata } from 'next';
import FavoriteButton from '@/components/ui/FavoriteButton';

export const revalidate = 86400; // 24 hours

export async function generateMetadata({ params }: { params: { id: string } }): Promise<Metadata> {
  try {
    const data = await footballApi.getTeamDetails(params.id);
    if (data?.[0]) {
      const { team } = data[0];
      return {
        title: `${team.name} | ملف الفريق - نور`,
        description: `كل شيء عن ${team.name}: إحصائيات الموسم، قائمة اللاعبين، النتائج الأخيرة، الانتقالات. تأسس ${team.founded} في ${team.country}.`,
        openGraph: { title: `${team.name} | نور`, images: [team.logo], type: 'website', locale: 'ar_SA' },
      };
    }
  } catch {}
  return { title: 'ملف الفريق | نور' };
}

export default async function TeamProfilePage({ params }: { params: { id: string } }) {
  try {
    const season = getCurrentSeason();
    const [detailsData, fixturesData, upcomingFixturesData, squadData, transfersData] = await Promise.all([
      footballApi.getTeamDetails(params.id),
      footballApi.getTeamFixtures(params.id, season, 10),
      footballApi.getNextTeamFixtures(params.id, season, 5).catch(() => []),
      footballApi.getTeamSquad(params.id),
      footballApi.getTeamTransfers(params.id).catch(() => []),
    ]);

    if (!detailsData || detailsData.length === 0) {
      return <div className="text-center p-10 text-white font-readex">بيانات الفريق غير متوفرة</div>;
    }

    const info = detailsData[0];
    const team = info.team;
    const venue = info.venue;
    const squad = squadData?.[0]?.players || [];
    const fixtures = fixturesData || [];
    const upcomingFixtures = (upcomingFixturesData || []).filter((fixture: any) => fixture.fixture?.status?.short === 'NS').slice(0, 5);
    const transfers = (transfersData || [])
      .flatMap((entry: any) =>
        (entry.transfers || []).map((transfer: any) => ({
          ...transfer,
          playerName: entry.player_name || entry.player?.name || null,
          playerId: entry.player_id || entry.player?.id || null,
          playerPhoto: entry.player_photo || entry.player?.photo || null,
          playerPosition: entry.player_position || entry.player?.position || null,
        }))
      )
      .sort((a: any, b: any) => {
        const aDate = a.date ? new Date(a.date).getTime() : 0;
        const bDate = b.date ? new Date(b.date).getTime() : 0;
        return bDate - aDate;
      })
      .slice(0, 8);
    const incomingTransfers = transfers.filter((transfer: any) => transfer.type === 'in').length;
    const outgoingTransfers = transfers.filter((transfer: any) => transfer.type === 'out').length;

    // Group squad by position
    const posOrder = ['Goalkeeper', 'Defender', 'Midfielder', 'Attacker'];
    const posAr: Record<string, string> = { 'Goalkeeper': 'حراسة المرمى', 'Defender': 'خط الدفاع', 'Midfielder': 'خط الوسط', 'Attacker': 'خط الهجوم' };
    const grouped = posOrder.map(pos => ({
      position: pos,
      label: posAr[pos] || pos,
      players: squad.filter((p: any) => p.position === pos),
    })).filter(g => g.players.length > 0);

    // Calculate form from last 5 fixtures
    const form = fixtures.slice(0, 5).map((f: any) => {
      const isHome = f.teams.home.id.toString() === params.id;
      if (f.goals.home > f.goals.away) return isHome ? 'W' : 'L';
      if (f.goals.home < f.goals.away) return isHome ? 'L' : 'W';
      return 'D';
    });
    const recentWindow = fixtures.slice(0, 5);
    const goalsFor = recentWindow.reduce((sum: number, fixture: any) => {
      const isHome = fixture.teams.home.id.toString() === params.id;
      return sum + (isHome ? fixture.goals.home ?? 0 : fixture.goals.away ?? 0);
    }, 0);
    const goalsAgainst = recentWindow.reduce((sum: number, fixture: any) => {
      const isHome = fixture.teams.home.id.toString() === params.id;
      return sum + (isHome ? fixture.goals.away ?? 0 : fixture.goals.home ?? 0);
    }, 0);
    const cleanSheets = recentWindow.filter((fixture: any) => {
      const isHome = fixture.teams.home.id.toString() === params.id;
      const conceded = isHome ? fixture.goals.away ?? 0 : fixture.goals.home ?? 0;
      return conceded === 0;
    }).length;
    const sectionLinks = [
      { href: '#overview', label: 'نظرة عامة' },
      { href: '#schedule', label: 'البرنامج' },
      { href: '#transfers', label: 'الانتقالات' },
      { href: '#squad', label: 'قائمة الفريق' },
    ];

    return (
      <div className="max-w-6xl mx-auto space-y-10 pb-20">
        <Link href="/matches" className="text-nor-green text-sm font-readex hover:underline flex items-center gap-2 w-max">
          <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="m15 18-6-6 6-6"/></svg>
          العودة للمباريات
        </Link>
        
        {/* Hero Header */}
        <div id="overview" className="bg-neutral-900 border border-neutral-800 rounded-3xl p-8 flex flex-col md:flex-row items-center md:items-start gap-8 relative overflow-hidden shadow-2xl">
           <div className="absolute top-0 left-0 w-full h-full opacity-10 blur-xl pointer-events-none" style={{ backgroundColor: `#${team.colors?.player?.primary || '00FF85'}` }}></div>
           
           <div className="relative z-10 w-40 h-40 bg-neutral-800/50 rounded-2xl border border-neutral-700 flex items-center justify-center p-5 shadow-xl">
             <img src={team.logo} alt={team.name} className="w-full h-full object-contain filter drop-shadow-lg" />
           </div>

           <div className="relative z-10 flex flex-col items-center md:items-start text-center md:text-right flex-1 pt-2">
             <h1 className="text-4xl sm:text-5xl font-bold font-readex mb-2 tracking-tight">{team.name}</h1>
             <p className="text-neutral-400 font-ibm mb-4 text-lg">{team.country} • تأسس {team.founded}</p>
             <div className="mb-4">
               <FavoriteButton
                 type="team"
                 item={{ id: String(team.id), name: team.name, logo: team.logo, country: team.country }}
               />
             </div>

             {/* Form Guide */}
             {form.length > 0 && (
               <div className="flex items-center gap-2 mb-6">
                 <span className="text-xs text-neutral-500 font-readex ml-2">الفورمة:</span>
                 {form.map((r: string, i: number) => (
                   <span key={i} className={`w-7 h-7 rounded-md flex items-center justify-center text-xs font-bold ${
                     r === 'W' ? 'bg-nor-green text-black' : r === 'D' ? 'bg-neutral-600 text-white' : 'bg-red-500 text-white'
                   }`}>{r === 'W' ? 'ف' : r === 'D' ? 'ت' : 'خ'}</span>
                 ))}
               </div>
             )}

             <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 w-full">
                <div className="bg-neutral-800/40 rounded-xl p-3 border border-neutral-700/30 backdrop-blur-sm">
                  <span className="block text-[10px] text-neutral-500 font-readex uppercase">الملعب</span>
                  <span className="font-bold text-white font-ibm text-sm">{venue.name}</span>
                </div>
                <div className="bg-neutral-800/40 rounded-xl p-3 border border-neutral-700/30 backdrop-blur-sm">
                  <span className="block text-[10px] text-neutral-500 font-readex uppercase">السعة</span>
                  <span className="font-bold text-white font-ibm text-sm">{venue.capacity?.toLocaleString() || '-'}</span>
                </div>
                <div className="bg-neutral-800/40 rounded-xl p-3 border border-neutral-700/30 backdrop-blur-sm">
                  <span className="block text-[10px] text-neutral-500 font-readex uppercase">اللاعبون</span>
                  <span className="font-bold text-white font-ibm text-sm">{squad.length}</span>
                </div>
                <div className="bg-neutral-800/40 rounded-xl p-3 border border-neutral-700/30 backdrop-blur-sm">
                  <span className="block text-[10px] text-neutral-500 font-readex uppercase">المدينة</span>
                  <span className="font-bold text-white font-ibm text-sm">{venue.city || team.country}</span>
                </div>
             </div>
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
            <p className="text-sm text-neutral-500 font-readex">أهداف آخر 5 مباريات</p>
            <p className="mt-2 text-3xl font-bold font-readex text-white">{goalsFor}</p>
            <p className="mt-2 text-xs text-neutral-500 font-ibm">يعكس الإنتاج الهجومي القريب للفريق</p>
          </div>
          <div className="rounded-3xl border border-neutral-800 bg-neutral-900 p-5">
            <p className="text-sm text-neutral-500 font-readex">استقبل الفريق</p>
            <p className="mt-2 text-3xl font-bold font-readex text-red-400">{goalsAgainst}</p>
            <p className="mt-2 text-xs text-neutral-500 font-ibm">عدد الأهداف المستقبلة في آخر خمس مباريات</p>
          </div>
          <div className="rounded-3xl border border-neutral-800 bg-neutral-900 p-5">
            <p className="text-sm text-neutral-500 font-readex">شباك نظيفة</p>
            <p className="mt-2 text-3xl font-bold font-readex text-nor-green">{cleanSheets}</p>
            <p className="mt-2 text-xs text-neutral-500 font-ibm">عدد المباريات التي خرج فيها الفريق دون استقبال</p>
          </div>
          <div className="rounded-3xl border border-neutral-800 bg-neutral-900 p-5">
            <p className="text-sm text-neutral-500 font-readex">حركة السوق</p>
            <p className="mt-2 text-3xl font-bold font-readex text-white">{incomingTransfers + outgoingTransfers}</p>
            <p className="mt-2 text-xs text-neutral-500 font-ibm">{incomingTransfers} وافد • {outgoingTransfers} مغادر</p>
          </div>
        </div>

        {/* Results + Transfers */}
        <div id="schedule" className="grid grid-cols-1 lg:grid-cols-12 gap-8">
           {/* Recent Results */}
           <div className="lg:col-span-7 space-y-4">
              <h3 className="text-2xl font-bold font-readex border-r-4 border-nor-green pr-4">آخر النتائج</h3>
              <div className="space-y-2">
                 {fixtures.slice(0, 8).map((f: any) => {
                    const isHome = f.teams.home.id.toString() === params.id;
                    const result = f.goals.home > f.goals.away ? (isHome ? 'W' : 'L') : f.goals.home === f.goals.away ? 'D' : (isHome ? 'L' : 'W');
                    
                    return (
                      <Link href={`/matches/${f.fixture.id}`} key={f.fixture.id} className="flex items-center gap-3 p-3 bg-neutral-900 border border-neutral-800 rounded-xl hover:bg-neutral-800/70 transition-all group">
                         <span className={`w-7 h-7 rounded-md flex items-center justify-center font-bold text-xs shrink-0 ${result === 'W' ? 'bg-nor-green text-black' : result === 'D' ? 'bg-neutral-700 text-white' : 'bg-red-500 text-white'}`}>
                            {result === 'W' ? 'ف' : result === 'D' ? 'ت' : 'خ'}
                         </span>
                         <div className="flex-1 min-w-0">
                           <span className="text-[10px] text-neutral-500 font-readex block">{f.league.name} • {new Date(f.fixture.date).toLocaleDateString('ar-EG', { month: 'short', day: 'numeric' })}</span>
                           <div className="flex items-center gap-2 font-ibm text-sm">
                              <img src={f.teams.home.logo} alt="" className="w-4 h-4 object-contain" />
                              <span className={isHome ? 'font-bold' : ''}>{f.teams.home.name}</span>
                              <span className="text-nor-green font-bold">{f.goals.home}-{f.goals.away}</span>
                              <span className={!isHome ? 'font-bold' : ''}>{f.teams.away.name}</span>
                              <img src={f.teams.away.logo} alt="" className="w-4 h-4 object-contain" />
                           </div>
                         </div>
                      </Link>
                    );
                 })}
                 {fixtures.length === 0 && <p className="text-neutral-500 font-ibm p-4">لا توجد مواجهات حديثة.</p>}
              </div>
           </div>

           {/* Upcoming fixtures */}
           <div className="lg:col-span-5 space-y-4">
              <h3 className="text-2xl font-bold font-readex border-r-4 border-nor-green pr-4">القادم في الجدول</h3>
              {upcomingFixtures.length > 0 ? (
                <div className="space-y-2">
                  {upcomingFixtures.map((fixture: any) => {
                    const isHome = fixture.teams.home.id.toString() === params.id;
                    const opponent = isHome ? fixture.teams.away : fixture.teams.home;
                    return (
                      <Link
                        key={fixture.fixture.id}
                        href={`/matches/${fixture.fixture.id}`}
                        className="flex items-center gap-3 rounded-xl border border-neutral-800 bg-neutral-900 p-4 hover:bg-neutral-800/70 transition-all"
                      >
                        <img src={opponent.logo} alt={opponent.name} className="w-10 h-10 object-contain shrink-0" />
                        <div className="flex-1 min-w-0">
                          <p className="text-sm text-neutral-500 font-readex">{fixture.league.name}</p>
                          <p className="truncate text-base font-bold font-ibm text-white">
                            {isHome ? 'ضد' : 'أمام'} {opponent.name}
                          </p>
                          <p className="text-xs text-neutral-500 font-ibm">
                            {new Date(fixture.fixture.date).toLocaleDateString('ar-EG', { month: 'short', day: 'numeric' })} •{' '}
                            {new Date(fixture.fixture.date).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })}
                          </p>
                        </div>
                      </Link>
                    );
                  })}
                </div>
              ) : (
                <p className="text-neutral-500 font-ibm p-4 bg-neutral-900 border border-neutral-800 rounded-xl">لا توجد مباريات قادمة متاحة حالياً.</p>
              )}

              <div className="grid gap-2">
                <Link href={`/compare/teams`} className="w-full text-center py-2.5 bg-neutral-900 border border-neutral-800 rounded-lg text-sm font-readex text-neutral-300 hover:text-nor-green hover:border-nor-green/50 transition-all">
                  مقارنة موسمية مع فريق آخر
                </Link>
                <Link href={`/h2h`} className="w-full text-center py-2.5 bg-neutral-900 border border-neutral-800 rounded-lg text-sm font-readex text-neutral-300 hover:text-nor-green hover:border-nor-green/50 transition-all">
                  سجل المواجهات المباشرة
                </Link>
              </div>
           </div>
        </div>

        <div id="transfers" className="grid grid-cols-1 lg:grid-cols-12 gap-8">
           <div className="lg:col-span-7 space-y-4">
              <h3 className="text-2xl font-bold font-readex border-r-4 border-nor-green pr-4">آخر الانتقالات</h3>
              {transfers.length > 0 ? (
                <div className="space-y-2">
                  {transfers.map((t: any, idx: number) => (
                    <div key={idx} className="flex items-center gap-3 p-3 bg-neutral-900 border border-neutral-800 rounded-xl">
                      <div className="flex flex-col items-center gap-0.5 shrink-0 w-8">
                        <img src={t.teams?.out?.logo} alt="" className="w-5 h-5 object-contain" />
                        <span className="text-nor-green text-[10px]">↓</span>
                        <img src={t.teams?.in?.logo} alt="" className="w-5 h-5 object-contain" />
                      </div>
                      <div className="flex-1 min-w-0">
                        {t.playerId ? (
                          <Link href={`/players/${t.playerId}`} className="block text-sm font-ibm font-bold truncate hover:text-nor-green transition-colors">
                            {t.playerName || 'لاعب غير محدد'}
                          </Link>
                        ) : (
                          <p className="text-sm font-ibm font-bold truncate">{t.playerName || 'لاعب غير محدد'}</p>
                        )}
                        <p className="text-xs text-neutral-500 font-readex">
                          {t.date || 'تاريخ غير محدد'} • {t.type || 'انتقال'}
                        </p>
                        <p className="text-[11px] text-neutral-500 font-ibm truncate">
                          {t.teams?.out?.name || 'غير محدد'} ← {t.teams?.in?.name || 'غير محدد'}
                        </p>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-neutral-500 font-ibm p-4 bg-neutral-900 border border-neutral-800 rounded-xl">لا توجد انتقالات مسجلة.</p>
              )}
           </div>

           <div className="lg:col-span-5 space-y-4">
             <h3 className="text-2xl font-bold font-readex border-r-4 border-nor-green pr-4">روابط النادي</h3>
             <div className="rounded-3xl border border-neutral-800 bg-neutral-900 p-5 space-y-3">
               <Link href={`/injuries?league=39`} className="flex items-center justify-between rounded-2xl border border-neutral-800 bg-neutral-950 px-4 py-3 text-sm font-readex text-neutral-300 hover:border-nor-green hover:text-nor-green transition-colors">
                 <span>تقرير الإصابات</span>
                 <span>🏥</span>
               </Link>
               <Link href={`/transfers?league=39`} className="flex items-center justify-between rounded-2xl border border-neutral-800 bg-neutral-950 px-4 py-3 text-sm font-readex text-neutral-300 hover:border-nor-green hover:text-nor-green transition-colors">
                 <span>سوق الانتقالات</span>
                 <span>🔄</span>
               </Link>
               <Link href={`/matches`} className="flex items-center justify-between rounded-2xl border border-neutral-800 bg-neutral-950 px-4 py-3 text-sm font-readex text-neutral-300 hover:border-nor-green hover:text-nor-green transition-colors">
                 <span>جدول المباريات</span>
                 <span>📅</span>
               </Link>
             </div>
           </div>
        </div>

        {/* Full Squad by Position */}
        <div id="squad" className="space-y-6">
          <h3 className="text-2xl font-bold font-readex border-r-4 border-nor-green pr-4">قائمة الفريق الكاملة ({squad.length} لاعب)</h3>
          
          {grouped.map((group) => (
            <div key={group.position}>
              <h4 className="text-sm font-readex font-bold text-neutral-400 uppercase tracking-wider mb-3 flex items-center gap-2">
                <span className={`w-2 h-2 rounded-full ${
                  group.position === 'Goalkeeper' ? 'bg-yellow-400' : group.position === 'Defender' ? 'bg-blue-400' : group.position === 'Midfielder' ? 'bg-nor-green' : 'bg-red-400'
                }`}></span>
                {group.label} ({group.players.length})
              </h4>
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
                {group.players.map((p: any) => (
                  <Link href={`/players/${p.id}`} key={p.id} className="flex items-center gap-3 p-3 bg-neutral-900 border border-neutral-800 rounded-xl hover:bg-neutral-800/70 hover:border-neutral-700 transition-all group">
                    <div className="w-10 h-10 rounded-full bg-neutral-800 border border-neutral-700 overflow-hidden shrink-0">
                      <img src={p.photo} alt={p.name} className="w-full h-full object-cover" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <span className="text-sm font-ibm font-bold text-white group-hover:text-nor-green transition-colors block truncate">{p.name}</span>
                      <span className="text-[10px] text-neutral-500 font-readex">#{p.number || '-'} • {p.age ? `${p.age} عام` : ''}</span>
                    </div>
                  </Link>
                ))}
              </div>
            </div>
          ))}
          {squad.length === 0 && <p className="text-center text-neutral-500 font-ibm p-10">قائمة اللاعبين غير متوفرة حالياً.</p>}
        </div>
      </div>
    );
  } catch (error) {
    console.error('Team Hub Error:', error);
    return <div className="text-center p-10 font-readex text-red-500">حدث خطأ أثناء جلب بيانات الفريق</div>;
  }
}
