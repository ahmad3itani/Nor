"use client";
import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';

export default function TopAssistsTable({ leagueId = '39' }: { leagueId?: string }) {
  const { data, isLoading } = useQuery({
    queryKey: ['assists', leagueId],
    queryFn: async () => {
      const res = await fetch(`/api/football/analytics/assists?league=${leagueId}`);
      if (!res.ok) throw new Error('Failed to fetch');
      return res.json();
    }
  });

  if (isLoading) {
    return <div className="animate-pulse space-y-4">
      {[...Array(5)].map((_, i) => (
        <div key={i} className="h-12 bg-neutral-800 rounded"></div>
      ))}
    </div>;
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm text-right font-ibm">
        <thead className="text-xs text-neutral-500 border-b border-neutral-800">
          <tr>
            <th className="py-2 px-2 w-8">#</th>
            <th className="py-2 px-2">اللاعب</th>
            <th className="py-2 px-2 hidden sm:table-cell">الفريق</th>
            <th className="py-2 px-2 text-center">صناعة</th>
            <th className="py-2 px-2 text-center text-neutral-500">لعب</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-neutral-800">
          {data?.slice(0, 5).map((item: any, idx: number) => {
            const assists = item.statistics[0].goals.assists || 0;
            const app = item.statistics[0].games.appearences || 0;
            return (
              <tr key={item.player.id} className="hover:bg-neutral-800/30 transition-colors">
                <td className="py-3 px-2 text-neutral-400">{idx + 1}</td>
                <td className="py-3 px-2 font-medium">
                  <Link href={`/players/${item.player.id}`} className="flex items-center gap-3 hover:text-nor-green transition-colors group">
                    <img src={item.player.photo} alt={item.player.name} className="w-8 h-8 rounded-full object-cover border border-neutral-700 group-hover:scale-110 transition-transform" />
                    <span className="truncate max-w-[120px] text-white" title={item.player.name}>{item.player.name}</span>
                  </Link>
                </td>
                <td className="py-3 px-2 hidden sm:table-cell">
                   <Link href={`/teams/${item.statistics[0].team.id}`} className="flex items-center gap-2 hover:text-nor-green transition-colors group">
                     <img src={item.statistics[0].team.logo} alt="team" className="w-4 h-4 object-contain group-hover:scale-110 transition-transform" />
                     <span className="text-neutral-400 text-xs group-hover:text-nor-green transition-colors">{item.statistics[0].team.name}</span>
                   </Link>
                </td>
                <td className="py-3 px-2 text-center font-bold text-nor-green">{assists}</td>
                <td className="py-3 px-2 text-center text-neutral-500">{app}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
