"use client";
import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';

export default function AnalyticsStandingsSnapshot({ leagueId, leagueName }: { leagueId: string; leagueName: string }) {
  const { data: standings, isLoading } = useQuery({
    queryKey: ['standings-analytics', leagueId],
    queryFn: async () => {
      const res = await fetch(`/api/football/standings?league=${leagueId}`);
      if (!res.ok) throw new Error('Failed');
      return res.json();
    },
    staleTime: 1800000,
  });

  const standingsList = standings?.[0]?.league?.standings?.[0] || [];

  if (isLoading) {
    return (
      <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 h-64 animate-pulse" />
    );
  }

  if (standingsList.length === 0) return null;

  return (
    <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold font-readex border-r-4 border-nor-green pr-3">ترتيب {leagueName}</h2>
        <Link href={`/matches?league=${leagueId}`} className="text-xs text-nor-green font-readex hover:underline">الترتيب الكامل</Link>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-neutral-500 font-readex text-xs border-b border-neutral-800">
              <th className="pb-3 text-right pr-2">#</th>
              <th className="pb-3 text-right">الفريق</th>
              <th className="pb-3 text-center">لعب</th>
              <th className="pb-3 text-center">فوز</th>
              <th className="pb-3 text-center">تعادل</th>
              <th className="pb-3 text-center">خسارة</th>
              <th className="pb-3 text-center">له</th>
              <th className="pb-3 text-center">عليه</th>
              <th className="pb-3 text-center">+/-</th>
              <th className="pb-3 text-center font-bold text-white">نقاط</th>
              <th className="pb-3 text-center hidden sm:table-cell">آخر 5</th>
            </tr>
          </thead>
          <tbody>
            {standingsList.slice(0, 10).map((team: any) => {
              let zoneClass = '';
              if (team.rank <= 4) zoneClass = 'border-r-2 border-nor-green';
              else if (team.rank === 5) zoneClass = 'border-r-2 border-blue-500';
              else if (team.rank > standingsList.length - 3) zoneClass = 'border-r-2 border-red-500';

              return (
                <tr key={team.team.id} className={`border-b border-neutral-800/50 hover:bg-neutral-800/20 transition-colors ${zoneClass}`}>
                  <td className="py-3 pr-2 text-neutral-500 font-ibm">{team.rank}</td>
                  <td className="py-3">
                    <Link href={`/teams/${team.team.id}`} className="flex items-center gap-2 hover:text-nor-green transition-colors group">
                      <img src={team.team.logo} alt="" className="w-5 h-5 object-contain" />
                      <span className="font-ibm font-medium truncate max-w-[140px]">{team.team.name}</span>
                    </Link>
                  </td>
                  <td className="py-3 text-center text-neutral-400">{team.all.played}</td>
                  <td className="py-3 text-center text-nor-green">{team.all.win}</td>
                  <td className="py-3 text-center text-neutral-400">{team.all.draw}</td>
                  <td className="py-3 text-center text-red-400">{team.all.lose}</td>
                  <td className="py-3 text-center">{team.all.goals.for}</td>
                  <td className="py-3 text-center text-neutral-400">{team.all.goals.against}</td>
                  <td className="py-3 text-center font-bold">{team.goalsDiff > 0 ? `+${team.goalsDiff}` : team.goalsDiff}</td>
                  <td className="py-3 text-center font-bold text-white text-base">{team.points}</td>
                  <td className="py-3 text-center hidden sm:table-cell">
                    <div className="flex gap-0.5 justify-center">
                      {team.form?.split('').slice(-5).map((char: string, ci: number) => (
                        <span key={ci} className={`w-4 h-4 rounded-full flex items-center justify-center text-[8px] font-bold text-white ${
                          char === 'W' ? 'bg-nor-green' : char === 'D' ? 'bg-neutral-600' : 'bg-red-500'
                        }`}>{char}</span>
                      ))}
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
