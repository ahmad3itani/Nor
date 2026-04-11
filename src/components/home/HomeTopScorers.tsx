"use client";
import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';

export default function HomeTopScorers() {
  const { data: scorers, isLoading } = useQuery({
    queryKey: ['top-scorers-home', '39'],
    queryFn: async () => {
      const res = await fetch('/api/football/analytics/scorers?league=39');
      if (!res.ok) throw new Error('Failed to fetch');
      return res.json();
    },
    staleTime: 3600000,
  });

  if (isLoading) {
    return (
      <div className="bg-neutral-900 rounded-2xl p-5 border border-neutral-800 animate-pulse">
        <div className="h-6 w-32 bg-neutral-800 rounded mb-4"></div>
        <div className="space-y-3">
          {[1, 2, 3].map(i => <div key={i} className="h-10 bg-neutral-800 rounded"></div>)}
        </div>
      </div>
    );
  }

  const topFive = (scorers || []).slice(0, 5);
  if (topFive.length === 0) return null;

  return (
    <div className="bg-neutral-900 rounded-2xl p-5 border border-neutral-800">
      <div className="flex items-center justify-between mb-4">
        <h3 className="font-readex font-bold text-lg flex items-center gap-2">
          <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-nor-green"><circle cx="12" cy="8" r="6"/><path d="M15.477 12.89 17 22l-5-3-5 3 1.523-9.11"/></svg>
          الهدافون
        </h3>
        <Link href="/analytics" className="text-xs text-nor-green font-readex hover:underline">المزيد</Link>
      </div>

      <div className="space-y-2">
        {topFive.map((entry: any, idx: number) => (
          <Link
            key={entry.player?.id || idx}
            href={`/players/${entry.player?.id}`}
            className="flex items-center gap-3 p-2 rounded-lg hover:bg-neutral-800/50 transition-colors group"
          >
            <span className={`w-5 text-center font-bold text-xs ${idx === 0 ? 'text-nor-green' : 'text-neutral-500'}`}>{idx + 1}</span>
            <img src={entry.player?.photo} alt="" className="w-7 h-7 rounded-full object-cover border border-neutral-700" />
            <div className="flex-1 min-w-0">
              <p className="text-sm font-ibm font-bold truncate group-hover:text-nor-green transition-colors">{entry.player?.name}</p>
              <p className="text-[10px] text-neutral-500 font-readex">{entry.statistics?.[0]?.team?.name}</p>
            </div>
            <span className="text-nor-green font-bold font-ibm text-sm">{entry.statistics?.[0]?.goals?.total || 0}</span>
          </Link>
        ))}
      </div>
    </div>
  );
}
