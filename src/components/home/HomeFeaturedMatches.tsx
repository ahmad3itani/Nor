"use client";

import Link from 'next/link';
import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { format } from 'date-fns';

export default function HomeFeaturedMatches() {
  const [today, setToday] = useState('');
  useEffect(() => { setToday(format(new Date(), 'yyyy-MM-dd')); }, []);

  const { data, isLoading } = useQuery({
    queryKey: ['featured-matches-home', today],
    queryFn: async () => {
      const res = await fetch(`/api/football/fixtures?date=${today}`);
      if (!res.ok) throw new Error('Failed');
      return res.json();
    },
    enabled: !!today,
    staleTime: 300000,
  });

  const matches = (Array.isArray(data) ? data : [])
    .filter((m: any) => ['NS', '1H', 'HT', '2H', 'ET', 'P'].includes(m.fixture?.status?.short))
    .slice(0, 6);

  if (isLoading) {
    return (
      <section className="space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-xl font-bold font-readex border-r-4 border-nor-green pr-3">مباريات اليوم</h2>
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {[1, 2, 3].map(i => (
            <div key={i} className="bg-neutral-900 border border-neutral-800 rounded-2xl h-28 animate-pulse" />
          ))}
        </div>
      </section>
    );
  }

  if (matches.length === 0) return null;

  return (
    <section className="space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-bold font-readex border-r-4 border-nor-green pr-3">أبرز مباريات اليوم</h2>
        <Link href="/matches" className="text-sm text-nor-green font-readex hover:underline">الجدول الكامل ←</Link>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
        {matches.map((match: any) => {
          const isLive = ['1H', 'HT', '2H', 'ET', 'P'].includes(match.fixture?.status?.short);
          const isNS = match.fixture?.status?.short === 'NS';

          return (
            <Link
              key={match.fixture.id}
              href={`/matches/${match.fixture.id}`}
              className="group bg-neutral-900 border border-neutral-800 rounded-2xl p-4 hover:border-nor-green/40 hover:bg-neutral-900/90 transition-all"
            >
              {/* League + time */}
              <div className="flex items-center justify-between mb-3">
                <div className="flex items-center gap-1.5">
                  <img src={match.league?.logo} alt="" className="w-4 h-4 object-contain" />
                  <span className="text-[11px] text-neutral-500 font-readex truncate max-w-[110px]">{match.league?.name}</span>
                </div>
                {isLive ? (
                  <span className="flex items-center gap-1 text-[11px] font-bold font-readex text-red-400">
                    <span className="w-1.5 h-1.5 rounded-full bg-red-500 animate-pulse" />
                    {match.fixture.status.short === 'HT' ? 'استراحة' : `${match.fixture.status.elapsed}'`}
                  </span>
                ) : isNS ? (
                  <span className="text-[11px] text-nor-green font-readex font-bold">
                    {new Date(match.fixture.date).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })}
                  </span>
                ) : (
                  <span className="text-[11px] text-neutral-500 font-readex">{match.fixture.status.long}</span>
                )}
              </div>

              {/* Teams + Score */}
              <div className="space-y-2">
                <div className="flex items-center justify-between gap-2">
                  <div className="flex items-center gap-2 flex-1 min-w-0">
                    <img src={match.teams?.home?.logo} alt="" className="w-7 h-7 object-contain shrink-0" />
                    <span className="font-readex font-bold text-sm text-white truncate group-hover:text-nor-green transition-colors">
                      {match.teams?.home?.name}
                    </span>
                  </div>
                  {isLive ? (
                    <span className="font-black font-ibm text-lg text-white shrink-0">{match.goals?.home ?? 0}</span>
                  ) : (
                    <span className="text-neutral-600 text-xs font-ibm shrink-0">—</span>
                  )}
                </div>

                <div className="flex items-center justify-between gap-2">
                  <div className="flex items-center gap-2 flex-1 min-w-0">
                    <img src={match.teams?.away?.logo} alt="" className="w-7 h-7 object-contain shrink-0" />
                    <span className="font-readex text-sm text-neutral-300 truncate">
                      {match.teams?.away?.name}
                    </span>
                  </div>
                  {isLive ? (
                    <span className="font-black font-ibm text-lg text-white shrink-0">{match.goals?.away ?? 0}</span>
                  ) : (
                    <span className="text-neutral-600 text-xs font-ibm shrink-0">—</span>
                  )}
                </div>
              </div>
            </Link>
          );
        })}
      </div>
    </section>
  );
}
