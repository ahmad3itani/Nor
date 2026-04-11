"use client";
import React, { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';
import { isLiveMatch } from '@/lib/fixtures';

export default function MiniMatchesWidget() {
  const [today, setToday] = useState('');
  useEffect(() => { setToday(new Date().toISOString().slice(0, 10)); }, []);

  const { data: matches, isLoading } = useQuery({
    queryKey: ['daily-fixtures', today, 'all'],
    queryFn: async () => {
      const res = await fetch(`/api/football/fixtures?date=${today}`);
      if (!res.ok) throw new Error('Failed to fetch matches');
      return res.json();
    },
    enabled: !!today,
    staleTime: 15000,
  });

  if (isLoading) {
    return (
      <div className="bg-neutral-900 rounded-xl p-6 border border-neutral-800 animate-pulse">
         <div className="h-6 w-32 bg-neutral-800 rounded mb-4"></div>
         <div className="space-y-3">
            {[1, 2, 3].map(i => <div key={i} className="h-16 bg-neutral-800 rounded"></div>)}
         </div>
      </div>
    );
  }

  if (!matches || matches.length === 0) return null;

  // Render top 5 matches on the sidebar
  const topMatches = matches.slice(0, 5);

  return (
    <div className="bg-neutral-900 rounded-xl p-6 border border-neutral-800">
      <div className="flex justify-between items-center mb-6">
        <h3 className="font-readex font-bold text-lg flex items-center gap-2">
           <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-nor-green"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
           أبرز المواجهات
        </h3>
      </div>

      <div className="space-y-3">
         {topMatches.map((match: any) => {
            const isLive = isLiveMatch(match);
            const homeGoals = match.goals.home ?? '-';
            const awayGoals = match.goals.away ?? '-';

            return (
              <Link href={`/matches/${match.fixture.id}`} key={match.fixture.id} className="flex flex-col bg-neutral-800/40 hover:bg-neutral-800 rounded-lg p-3 transition-colors border border-transparent hover:border-neutral-700">
                <div className="flex justify-between text-[10px] text-neutral-500 font-readex mb-2 border-b border-neutral-800/50 pb-1">
                   <span>{match.league.name}</span>
                   <span className={isLive ? 'text-nor-green font-bold animate-pulse' : ''}>
                      {match.fixture.status.short === 'NS' 
                         ? new Date(match.fixture.date).toLocaleTimeString('ar-EG', {hour: '2-digit', minute:'2-digit'}) 
                         : match.fixture.status.short}
                   </span>
                </div>
                <div className="flex items-center w-full font-ibm font-bold text-sm gap-1">
                   <div className="flex items-center gap-1.5 flex-1 min-w-0">
                      <img src={match.teams.home.logo} className="w-4 h-4 object-contain shrink-0" alt="" />
                      <span className="truncate text-xs sm:text-sm">{match.teams.home.name}</span>
                   </div>

                   <div className="shrink-0 min-w-[44px] text-center text-nor-green text-xs tracking-wider bg-black/40 py-0.5 px-1.5 rounded">
                      {homeGoals} : {awayGoals}
                   </div>

                   <div className="flex items-center gap-1.5 flex-1 justify-end min-w-0">
                      <span className="truncate text-xs sm:text-sm text-left" dir="ltr">{match.teams.away.name}</span>
                      <img src={match.teams.away.logo} className="w-4 h-4 object-contain shrink-0" alt="" />
                   </div>
                </div>
              </Link>
            );
         })}
      </div>

      <div className="grid grid-cols-2 gap-2 mt-4">
        <Link href="/matches" className="block w-full text-center bg-neutral-800/50 hover:bg-neutral-800 text-sm font-readex py-2 rounded-lg transition-colors border border-neutral-700/50">
           كل المباريات
        </Link>
        <Link href="/live" className="block w-full text-center bg-red-500/10 hover:bg-red-500/15 text-sm font-readex py-2 rounded-lg transition-colors border border-red-500/20 text-red-400">
           المباشر الآن
        </Link>
      </div>
    </div>
  );
}
