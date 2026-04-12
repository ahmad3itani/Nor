import Link from 'next/link';
import dynamic from 'next/dynamic';
import MatchStats from '@/components/matches/MatchStats';
import { footballApi } from '@/lib/football-api';
import type { Metadata } from 'next';
import Breadcrumbs from '@/components/ui/Breadcrumbs';

const MatchLineups = dynamic(() => import('@/components/matches/MatchLineups'), { ssr: false, loading: () => <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 h-[500px] animate-pulse" /> });
const MatchIntelligenceCard = dynamic(() => import('@/components/analytics/MatchIntelligenceCard'), { ssr: false, loading: () => <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 h-64 animate-pulse" /> });
const MatchPrediction = dynamic(() => import('@/components/matches/MatchPrediction'), { ssr: false });

export const revalidate = 60; // 1 minute

export async function generateMetadata({ params }: { params: { id: string } }): Promise<Metadata> {
  try {
    const data = await footballApi.getFixtureDetails(params.id);
    if (data?.[0]) {
      const m = data[0];
      return {
        title: `${m.teams.home.name} ضد ${m.teams.away.name} | غولياذور`,
        description: `${m.league.name} - ${m.teams.home.name} ${m.goals?.home ?? ''} - ${m.goals?.away ?? ''} ${m.teams.away.name}. تفاصيل المباراة، الإحصائيات، التشكيلات.`,
        openGraph: { title: `${m.teams.home.name} vs ${m.teams.away.name}`, type: 'article', locale: 'ar_SA' },
      };
    }
  } catch {}
  return { title: 'تفاصيل المباراة | غولياذور' };
}

export default async function MatchDetailsPage({ params }: { params: { id: string } }) {
  let match: any;
  try {
    const [fixtureData, statsData, eventsData, lineupsData] = await Promise.allSettled([
      footballApi.getFixtureDetails(params.id),
      footballApi.getFixtureStatistics(params.id),
      footballApi.getFixtureEvents(params.id),
      footballApi.getFixtureLineups(params.id),
    ]);
    const fixture = fixtureData.status === 'fulfilled' ? fixtureData.value?.[0] : null;
    if (!fixture) {
      return <div className="text-center p-10 text-white font-readex">تعذر تحميل بيانات المباراة</div>;
    }
    match = {
      ...fixture,
      statistics: statsData.status === 'fulfilled' ? (statsData.value ?? []) : [],
      events: eventsData.status === 'fulfilled' ? (eventsData.value ?? []) : [],
      lineups: lineupsData.status === 'fulfilled' ? (lineupsData.value ?? []) : [],
    };
  } catch {
    return <div className="text-center p-10 text-white font-readex">تعذر تحميل بيانات المباراة</div>;
  }

  const isLive = match.fixture.status.short === '1H' || match.fixture.status.short === '2H' || match.fixture.status.short === 'HT';
  
  // Format players from fixture if available (usually match.players exists in API-Football fixture response)
  const seasonStats: any[] = [];
  if (match.players && match.players.length === 2) {
      match.players.forEach((teamEntry: any) => {
         teamEntry.players.forEach((p: any) => {
            const stats = p.statistics[0];
            seasonStats.push({
               team: { id: teamEntry.team.id },
               player: { name: p.player.name, photo: p.player.photo },
               games: { rating: stats.games.rating, position: stats.games.position },
               goals: { total: stats.goals.total, assists: stats.goals.assists },
               passes: { accuracy: stats.passes.accuracy },
               dribbles: { success: stats.dribbles.success },
               shots: { total: stats.shots.total }
            });
         });
      });
  }

  return (
    <div className="max-w-5xl mx-auto space-y-12">
      <Breadcrumbs items={[
        { label: 'المباريات', href: '/matches' },
        { label: `${match.teams.home.name} ضد ${match.teams.away.name}` },
      ]} />

      {/* Hero Header */}
      <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-8 relative overflow-hidden shadow-xl">
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[500px] h-[500px] bg-nor-green/5 blur-[120px] rounded-full pointer-events-none"></div>

        <div className="flex flex-col items-center">
          <div className="text-neutral-400 font-readex text-sm mb-8 flex flex-col items-center gap-1">
            <span>{match.league.name} - {match.league.round}</span>
            <span>{new Date(match.fixture.date).toLocaleDateString('ar-EG', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'})}</span>
          </div>

          <div className="flex items-center justify-between w-full max-w-3xl">
             <Link href={`/teams/${match.teams.home.id}`} className="flex flex-col items-center gap-4 flex-1 hover:scale-105 transition-transform">
               <img src={match.teams.home.logo} className="w-24 h-24 sm:w-32 sm:h-32 object-contain filter drop-shadow-lg" alt={match.teams.home.name} />
               <h2 className="text-xl sm:text-2xl font-bold font-readex text-center">{match.teams.home.name}</h2>
             </Link>

             <div className="flex flex-col items-center justify-center px-4 sm:px-8">
                <div className={`text-5xl sm:text-7xl font-bold font-readex ${isLive ? 'text-nor-green drop-shadow-[0_0_20px_rgba(0,255,133,0.6)]' : 'text-white drop-shadow-glow'}`}>
                  {match.goals.home ?? 0} <span className="text-neutral-600 mx-2">-</span> {match.goals.away ?? 0}
                </div>
                <span className="text-neutral-400 text-sm mt-4 font-ibm tracking-widest uppercase bg-neutral-800 px-3 py-1 rounded-full">
                   {match.fixture.status.long} {isLive && <span className="text-nor-green ml-1">{match.fixture.status.elapsed}'</span>}
                </span>
             </div>

             <Link href={`/teams/${match.teams.away.id}`} className="flex flex-col items-center gap-4 flex-1 hover:scale-105 transition-transform">
               <img src={match.teams.away.logo} className="w-24 h-24 sm:w-32 sm:h-32 object-contain filter drop-shadow-lg" alt={match.teams.away.name} />
               <h2 className="text-xl sm:text-2xl font-bold font-readex text-center">{match.teams.away.name}</h2>
             </Link>
          </div>
        </div>
      </div>

      <MatchIntelligenceCard fixtureId={params.id} matchData={match} seasonStats={seasonStats.length > 0 ? (seasonStats as any) : undefined} />

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
         <div className="lg:col-span-8 space-y-8">
            {/* Extended Lineups Pitch */}
            {match.lineups && match.lineups.length > 0 && (
               <MatchLineups lineups={match.lineups} />
            )}
            
            {/* Extended Match Stats Grid */}
            {match.statistics && match.statistics.length > 0 && (
               <MatchStats statistics={match.statistics} />
            )}
         </div>

         <div className="lg:col-span-4 space-y-8">
             {/* Match Prediction Widget — show only for upcoming/live matches */}
             {(match.fixture.status.short === 'NS' || isLive) && (
               <MatchPrediction
                 fixtureId={params.id}
                 homeTeam={match.teams.home}
                 awayTeam={match.teams.away}
               />
             )}

             {/* Refined Events Timeline */}
             {match.events && match.events.length > 0 && (
               <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 h-[600px] overflow-y-auto hide-scrollbar sticky top-8">
                 <h3 className="text-xl font-bold font-readex mb-6 border-r-4 border-nor-green pr-3">سجل الأحداث</h3>
                 <div className="space-y-0 text-sm font-ibm relative before:absolute before:inset-0 before:ml-5 before:-translate-x-px md:before:mx-auto md:before:translate-x-0 before:h-full before:w-0.5 before:bg-gradient-to-b before:from-transparent before:via-neutral-800 before:to-transparent">
                    {match.events.map((event: any, idx: number) => {
                      const isHome = event.team.id === match.teams.home.id;
                      return (
                        <div key={idx} className="relative flex items-center justify-between md:justify-normal md:odd:flex-row-reverse group is-active py-3">
                          <div className={`flex items-center w-[calc(100%-4rem)] md:w-[calc(50%-2rem)] gap-3 ${isHome ? 'md:flex-row' : 'md:flex-row-reverse'} bg-neutral-800/20 p-2 rounded-lg border border-neutral-800`}>
                            <div className="flex flex-col flex-1 pl-2 md:pl-0">
                               <Link href={`/players/${event.player.id}`} className="text-white hover:text-nor-green transition-colors font-medium">
                                 {event.player.name}
                               </Link>
                               {event.assist?.name && (
                                 <span className="text-neutral-500 text-xs">مساعدة: {event.assist.name}</span>
                               )}
                               <span className="text-neutral-600 text-xs mt-1">{event.detail}</span>
                            </div>
                            
                            <img src={event.team.logo} className="w-6 h-6 object-contain hidden md:block" alt="" />
                          </div>
                          
                          <div className="absolute top-1/2 left-0 md:left-1/2 transform -translate-y-1/2 md:-translate-x-1/2 w-10 h-10 rounded-full bg-neutral-900 border-2 border-neutral-800 z-10 flex items-center justify-center font-bold text-xs text-neutral-400 group-hover:border-nor-green group-hover:text-nor-green transition-colors">
                             {event.time.elapsed}'
                          </div>
                        </div>
                      );
                    })}
                 </div>
               </div>
             )}
         </div>
      </div>

    </div>
  );
}
