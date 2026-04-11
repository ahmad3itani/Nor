"use client";
import React from 'react';
import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';

export default function MiniStandingsWidget({ leagueId = "39" }: { leagueId?: string }) {
  const { data: standings, isLoading } = useQuery({
    queryKey: ['standings', leagueId, 'mini'],
    queryFn: async () => {
      const res = await fetch(`/api/football/standings?league=${leagueId}`);
      if (!res.ok) throw new Error('Failed to fetch mini standings');
      return res.json();
    }
  });

  if (isLoading) {
    return (
      <div className="animate-pulse flex flex-col gap-3 mt-4">
        {[1, 2, 3, 4, 5].map((i) => (
          <div key={i} className="flex items-center justify-between p-2 rounded bg-neutral-800/50">
            <div className="flex gap-3">
              <div className="w-4 h-4 bg-neutral-700 rounded"></div>
              <div className="w-24 h-4 bg-neutral-700 rounded"></div>
            </div>
            <div className="w-6 h-4 bg-neutral-700 rounded"></div>
          </div>
        ))}
      </div>
    );
  }

  const standingsList = standings?.[0]?.league?.standings?.[0] || [];

  if (standingsList.length === 0) return null;

  // Render top 5
  const topTeams = standingsList.slice(0, 5);

  return (
    <div className="mt-4 flex flex-col gap-2">
      <div className="flex items-center justify-between text-xs text-neutral-500 font-readex pb-2 border-b border-neutral-800">
         <span>الفريق</span>
         <span className="w-8 text-center">نقاط</span>
      </div>
      {topTeams.map((teamData: any) => {
         const isTop = teamData.rank === 1;
         return (
           <Link href={`/teams/${teamData.team?.id || ''}`} key={teamData.rank} className="flex items-center justify-between p-2 rounded-lg hover:bg-neutral-800 transition-colors group">
             <div className="flex items-center gap-3">
               <span className={`font-bold font-ibm w-4 text-center ${isTop ? 'text-nor-green' : 'text-neutral-500'}`}>{teamData.rank}</span>
               <img src={teamData.team.logo} className="w-5 h-5 object-contain" alt="" />
               <span className="font-ibm text-sm text-neutral-300 group-hover:text-white transition-colors truncate max-w-[120px]">{teamData.team.name}</span>
             </div>
             <span className="font-bold text-sm w-8 text-center text-white">{teamData.points}</span>
           </Link>
         );
      })}
      
      <Link href={`/matches?league=${leagueId}`} className="block text-center mt-3 text-xs text-nor-green font-readex hover:underline">
        عرض الترتيب الكامل
      </Link>
    </div>
  );
}
