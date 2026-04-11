"use client";
import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';

export default function StandingsTable({ leagueId }: { leagueId: string }) {
  const { data, isLoading } = useQuery({
    queryKey: ['standings', leagueId],
    queryFn: async () => {
      const res = await fetch(`/api/football/standings?league=${leagueId}`);
      if (!res.ok) throw new Error('Failed to fetch');
      return res.json();
    }
  });

  if (isLoading) {
    return <div className="animate-pulse space-y-4">
      {[...Array(10)].map((_, i) => (
        <div key={i} className="h-8 bg-neutral-800 rounded"></div>
      ))}
    </div>;
  }

  const standings = data?.[0]?.league?.standings?.[0] || [];

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm text-right font-ibm">
        <thead className="text-xs text-neutral-400 border-b border-neutral-800">
          <tr>
            <th className="py-2 px-1.5 w-7">#</th>
            <th className="py-2 px-1.5">الفريق</th>
            <th className="py-2 px-1.5 text-center w-7 hidden xs:table-cell" title="لعب">ل</th>
            <th className="py-2 px-1.5 text-center w-7 hidden sm:table-cell" title="فاز">ف</th>
            <th className="py-2 px-1.5 text-center w-7 hidden sm:table-cell" title="تعادل">ت</th>
            <th className="py-2 px-1.5 text-center w-7 hidden sm:table-cell" title="خسر">خ</th>
            <th className="py-2 px-1.5 text-center w-9 hidden xs:table-cell">+/-</th>
            <th className="py-2 px-1.5 text-center font-bold w-9">نقاط</th>
            <th className="py-2 px-1.5 text-center hidden md:table-cell">آخر 5</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-neutral-800">
          {standings.map((team: any) => {
            let zoneColor = '';
            if (team.rank <= 4) zoneColor = 'bg-nor-green/5 border-l-2 border-nor-green';
            else if (team.rank === 5) zoneColor = 'bg-blue-500/5 border-l-2 border-blue-500';
            else if (team.rank > standings.length - 3) zoneColor = 'bg-red-500/5 border-l-2 border-red-500';

            return (
            <tr key={team.team.id} className={`hover:bg-neutral-800/30 transition-colors ${zoneColor}`}>
              <td className="py-2.5 px-1.5 text-neutral-400 text-xs">{team.rank}</td>
              <td className="py-2.5 px-1.5 font-medium">
                <Link href={`/teams/${team.team.id}`} className="flex items-center gap-1.5 hover:text-nor-green transition-colors group">
                  <img src={team.team.logo} alt={team.team.name} className="w-4 h-4 object-contain shrink-0" />
                  <span className="truncate max-w-[90px] sm:max-w-[120px] text-xs sm:text-sm" title={team.team.name}>{team.team.name}</span>
                </Link>
              </td>
              <td className="py-2.5 px-1.5 text-center text-xs hidden xs:table-cell">{team.all.played}</td>
              <td className="py-2.5 px-1.5 text-center text-xs text-nor-green hidden sm:table-cell">{team.all.win}</td>
              <td className="py-2.5 px-1.5 text-center text-xs text-neutral-400 hidden sm:table-cell">{team.all.draw}</td>
              <td className="py-2.5 px-1.5 text-center text-xs text-red-500 hidden sm:table-cell">{team.all.lose}</td>
              <td className="py-2.5 px-1.5 text-center text-xs whitespace-nowrap hidden xs:table-cell" dir="ltr">{team.goalsDiff > 0 ? `+${team.goalsDiff}` : team.goalsDiff}</td>
              <td className="py-2.5 px-1.5 text-center text-xs font-bold">{team.points}</td>
              <td className="py-2.5 px-1.5 hidden md:table-cell">
                <div className="flex items-center gap-1 justify-center" dir="ltr">
                  {team.form?.split('').map((char: string, i: number) => (
                    <span
                      key={i}
                      className={`w-4 h-4 flex items-center justify-center text-[9px] rounded-full text-white font-bold
                        ${char === 'W' ? 'bg-nor-green' : char === 'D' ? 'bg-neutral-500' : 'bg-red-500'}
                      `}
                      title={char === 'W' ? 'فوز' : char === 'D' ? 'تعادل' : 'خسارة'}
                    >
                      {char}
                    </span>
                  ))}
                </div>
              </td>
            </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
