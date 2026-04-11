"use client";
import React from 'react';
import { useQuery } from '@tanstack/react-query';
import dynamic from 'next/dynamic';
import LivePressureBar from './LivePressureBar';

const D3HeatMap = dynamic(() => import('./D3HeatMap'), { ssr: false, loading: () => <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 h-64 animate-pulse" /> });
const PlayerComparisonRadar = dynamic(() => import('./PlayerComparisonRadar'), { ssr: false, loading: () => <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 h-64 animate-pulse" /> });

export default function MatchIntelligenceCard({ fixtureId, matchData, seasonStats }: { fixtureId: string, matchData: any, seasonStats?: any }) {
  // Try to fetch predictions for advanced stats
  const { data: predictions } = useQuery({
    queryKey: ['predictions', fixtureId],
    queryFn: async () => {
       const res = await fetch(`/api/football/analytics/predictions?fixture=${fixtureId}`);
       if (!res.ok) throw new Error('Failed');
       return res.json();
    },
    staleTime: 3600000 // 1 hour caching
  });

  // Try to fetch an AI punditry summary based on context
  const { data: punditry } = useQuery({
    queryKey: ['punditry', fixtureId, matchData.goals.home, matchData.goals.away],
    queryFn: async () => {
       const context = `المباراة بين ${matchData.teams.home.name} و ${matchData.teams.away.name} في بطولة ${matchData.league.name}. النتيجة: ${matchData.goals.home || 0} - ${matchData.goals.away || 0}. الاستحواذ: ${matchData.statistics?.[0]?.statistics?.find((s:any) => s.type === 'Ball Possession')?.value || '50%'} ل${matchData.teams.home.name}. الدقيقة الحالية: ${matchData.fixture.status.elapsed}.`;
       const res = await fetch(`/api/football/punditry?fixture=${fixtureId}&context=${encodeURIComponent(context)}`);
       if (!res.ok) throw new Error('Failed');
       return res.json();
    },
    staleTime: 300000, // 5 min
    enabled: matchData.fixture.status.short !== 'NS'
  });

  const isLive = ['1H', '2H', 'HT'].includes(matchData.fixture.status.short);
  
  // Find top players for comparison if stats exist
  const getTopPlayer = (teamId: number) => {
    if (!seasonStats) return null;
    const teamStats = seasonStats.filter((s:any) => s.team.id === teamId);
    if (!teamStats.length) return null;
    // Sort by rating
    teamStats.sort((a:any, b:any) => parseFloat(b.games.rating || '0') - parseFloat(a.games.rating || '0'));
    return teamStats[0]; // best player
  };

  const homeTopPlayer = getTopPlayer(matchData.teams.home.id);
  const awayTopPlayer = getTopPlayer(matchData.teams.away.id);

  // Pressure bar metrics
  const possHome = parseInt(matchData.statistics?.[0]?.statistics?.find((s:any) => s.type === 'Ball Possession')?.value) || 50;
  const possAway = 100 - possHome;
  
  const shotsHome = matchData.statistics?.[0]?.statistics?.find((s:any) => s.type === 'Total Shots')?.value || 0;
  const shotsAway = matchData.statistics?.[1]?.statistics?.find((s:any) => s.type === 'Total Shots')?.value || 0;

  return (
    <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 md:p-8 space-y-8 shadow-2xl relative overflow-hidden">
      {/* Background Decor */}
      <div className="absolute top-0 right-0 w-96 h-96 bg-nor-green/5 blur-3xl pointer-events-none rounded-full -translate-y-1/2 translate-x-1/4"></div>

      {/* AI Punditry Header */}
      <div className="relative z-10 border-b border-neutral-800/50 pb-6">
        <h3 className="font-readex text-nor-green text-sm flex items-center gap-2 mb-4">
           <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>
           رؤية "نور" التحليلية
        </h3>
        <p className="font-almarai text-2xl md:text-3xl font-bold leading-tight text-white drop-shadow-md">
           {punditry?.summary || (matchData.fixture.status.short === 'NS' ? "بانتظار صافرة البداية لتحليل المعطيات التكتيكية للمواجهة." : "يتم توليد التحليل التكتيكي المباشر...")}
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 relative z-10">
        
        {/* Left Column: Pressure & Predictions */}
        <div className="space-y-8">
           {/* Prediction Block */}
           {predictions && predictions.length > 0 && (
              <div className="bg-neutral-800/40 border border-neutral-700/50 rounded-2xl p-5 backdrop-blur-sm">
                 <h4 className="font-readex font-bold text-sm text-neutral-400 mb-4 text-center">نسبة الفوز المتوقعة (الخوارزمية)</h4>
                 <div className="flex h-4 rounded-full overflow-hidden text-[10px] font-bold font-ibm text-center">
                    <div style={{ width: predictions[0].predictions.percent.home }} className="bg-nor-green text-black flex items-center justify-center transition-all duration-1000">
                       {predictions[0].predictions.percent.home}
                    </div>
                    <div style={{ width: predictions[0].predictions.percent.draw }} className="bg-neutral-500 text-white flex items-center justify-center transition-all duration-1000 border-l border-r border-neutral-900 border-opacity-50">
                       {predictions[0].predictions.percent.draw}
                    </div>
                    <div style={{ width: predictions[0].predictions.percent.away }} className="bg-nor-white text-black flex items-center justify-center transition-all duration-1000">
                       {predictions[0].predictions.percent.away}
                    </div>
                 </div>
                 <div className="flex justify-between mt-2 text-xs font-readex text-neutral-500">
                    <span className="truncate max-w-[80px]" title={matchData.teams.home.name}>{matchData.teams.home.name}</span>
                    <span>تعادل</span>
                    <span className="truncate max-w-[80px]" title={matchData.teams.away.name}>{matchData.teams.away.name}</span>
                 </div>
              </div>
           )}

           {/* Live Pressure */}
           <div className="bg-neutral-800/40 border border-neutral-700/50 rounded-2xl p-5 backdrop-blur-sm space-y-6">
              <h4 className="font-readex font-bold text-sm text-white flex items-center gap-2">
                 مؤشر الضغط الهجومي
                 {isLive && <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse drop-shadow-[0_0_5px_rgba(239,68,68,1)]"></span>}
              </h4>
              <LivePressureBar 
                homeTeamName={matchData.teams.home.name}
                awayTeamName={matchData.teams.away.name}
                homeValue={possHome}
                awayValue={possAway}
                label="الاستحواذ %"
              />
              <LivePressureBar 
                homeTeamName={matchData.teams.home.name}
                awayTeamName={matchData.teams.away.name}
                homeValue={shotsHome}
                awayValue={shotsAway}
                label="إجمالي التسديدات"
              />
           </div>

           {/* Player Comparison Radar */}
           {homeTopPlayer && awayTopPlayer && (
              <div className="bg-neutral-800/40 border border-neutral-700/50 rounded-2xl p-5 backdrop-blur-sm flex flex-col items-center">
                 <h4 className="font-readex font-bold text-sm text-neutral-400 mb-2">مقارنة نجوم الفريقين</h4>
                 <div className="flex justify-between items-center w-full mb-6 text-xs font-ibm font-bold">
                    <span className="text-nor-green flex items-center gap-1"><span className="w-3 h-3 rounded bg-nor-green"></span> {homeTopPlayer.player.name.split(' ').slice(-1)[0]}</span>
                    <span className="text-nor-white flex items-center gap-1">{awayTopPlayer.player.name.split(' ').slice(-1)[0]} <span className="w-3 h-3 rounded bg-nor-white"></span></span>
                 </div>
                 <PlayerComparisonRadar 
                     player1={{
                       name: homeTopPlayer.player.name,
                       color: '#00FF85',
                       stats: [homeTopPlayer.goals.total||0, homeTopPlayer.goals.assists||0, parseInt(homeTopPlayer.passes.accuracy||'0') / 10, homeTopPlayer.dribbles.success||0, parseFloat(homeTopPlayer.games.rating||'0'), homeTopPlayer.shots.total||0]
                    }}
                    player2={{
                       name: awayTopPlayer.player.name,
                       color: '#FFFFFF',
                       stats: [awayTopPlayer.goals.total||0, awayTopPlayer.goals.assists||0, parseInt(awayTopPlayer.passes.accuracy||'0') / 10, awayTopPlayer.dribbles.success||0, parseFloat(awayTopPlayer.games.rating||'0'), awayTopPlayer.shots.total||0]
                    }}
                 />
              </div>
           )}
        </div>

        {/* Right Column: Player D3 Heatmap Highlight */}
        {homeTopPlayer && (
           <div className="bg-neutral-800/40 border border-neutral-700/50 rounded-2xl p-5 backdrop-blur-sm flex flex-col justify-center items-center">
               <h4 className="font-readex font-bold text-sm text-white mb-6 w-full text-right border-r-2 border-nor-green pr-2">
                  نجم المحور - {homeTopPlayer.player.name}
               </h4>
               <D3HeatMap 
                  playerPhoto={homeTopPlayer.player.photo}
                  position={homeTopPlayer.games.position}
                  intensity={parseFloat(homeTopPlayer.games.rating) || 7}
               />
               <div className="w-full mt-6 grid grid-cols-3 text-center divide-x border-t border-neutral-700 pt-4 divide-neutral-700 rtl:divide-x-reverse">
                  <div>
                     <div className="text-xs text-neutral-500 font-readex mb-1">التقييم</div>
                     <div className="text-lg font-bold font-ibm text-nor-green">{parseFloat(homeTopPlayer.games.rating).toFixed(1)}</div>
                  </div>
                  <div>
                     <div className="text-xs text-neutral-500 font-readex mb-1">أهداف</div>
                     <div className="text-lg font-bold font-ibm text-white">{homeTopPlayer.goals.total || 0}</div>
                  </div>
                  <div>
                     <div className="text-xs text-neutral-500 font-readex mb-1">دقة التمرير</div>
                     <div className="text-lg font-bold font-ibm text-white">{homeTopPlayer.passes.accuracy || 0}%</div>
                  </div>
               </div>
           </div>
        )}

      </div>
    </div>
  );
}
