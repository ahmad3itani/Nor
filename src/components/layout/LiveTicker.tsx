"use client";
import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';

export default function LiveTicker() {
  const { data: matches, isLoading } = useQuery({
    queryKey: ['live-matches'],
    queryFn: async () => {
      const res = await fetch('/api/football/live');
      if (!res.ok) throw new Error('Failed to fetch live matches');
      return res.json();
    },
    refetchInterval: 30000, // 30s
  });

  if (isLoading || !matches || matches.length === 0) {
    return (
      <div className="bg-neutral-900 border-b border-neutral-800 h-10 flex items-center px-4 overflow-hidden">
        <span className="text-nor-green text-xs font-bold font-readex tracking-widest mr-4 flex items-center gap-2">
          <span className="w-2 h-2 rounded-full bg-nor-green animate-pulse"></span>
          مباشر
        </span>
        <div className="text-xs text-neutral-500 font-readex">لا توجد مباريات جارية حالياً</div>
      </div>
    );
  }

  return (
    <div className="bg-neutral-900 border-b border-neutral-800 h-10 flex items-center overflow-hidden whitespace-nowrap">
      <div className="px-4 flex items-center border-l border-neutral-800 h-full z-10 bg-neutral-900 shadow-[10px_0_10px_rgba(23,23,23,1)]">
        <Link href="/live" className="text-nor-green text-xs font-bold font-readex tracking-widest flex items-center gap-2 hover:text-white transition-colors">
          <span className="w-2 h-2 rounded-full bg-nor-green animate-pulse"></span>
          مباشر
        </Link>
      </div>
      
      <div className="flex-1 overflow-hidden relative opacity-0 animate-[fadeIn_0.5s_ease-out_forwards]">
        <div className="inline-flex gap-8 hover:[animation-play-state:paused] animate-ticker pl-[100%]">
          {matches.map((match: any) => (
            <Link key={match.fixture.id} href={`/matches/${match.fixture.id}`} className="flex items-center gap-3 font-readex text-sm hover:text-nor-green transition-colors">
              <span className="text-neutral-400 text-xs w-8 text-center">{match.fixture.status.elapsed}'</span>
              <div className="flex items-center gap-1.5">
                <span className="font-medium text-white">{match.teams.home.name}</span>
                <span className="font-bold text-nor-green mx-1">
                  {match.goals.home ?? 0} - {match.goals.away ?? 0}
                </span>
                <span className="font-medium text-white">{match.teams.away.name}</span>
              </div>
            </Link>
          ))}
          {/* Duplicate for infinite scroll effect */}
          {matches.map((match: any) => (
            <Link key={`${match.fixture.id}-dup`} href={`/matches/${match.fixture.id}`} className="flex items-center gap-3 font-readex text-sm hover:text-nor-green transition-colors">
              <span className="text-neutral-400 text-xs w-8 text-center">{match.fixture.status.elapsed}'</span>
              <div className="flex items-center gap-1.5">
                <span className="font-medium text-white">{match.teams.home.name}</span>
                <span className="font-bold text-nor-green mx-1">
                  {match.goals.home ?? 0} - {match.goals.away ?? 0}
                </span>
                <span className="font-medium text-white">{match.teams.away.name}</span>
              </div>
            </Link>
          ))}
        </div>
      </div>
    </div>
  );
}
