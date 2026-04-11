"use client";
import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import Link from 'next/link';
import TeamPairSelector from '@/components/teams/TeamPairSelector';

type TeamOption = {
  id: number;
  name: string;
  logo: string;
  country: string;
  founded?: number | null;
  venueName?: string | null;
};

export default function H2HPage() {
  const [leagueId, setLeagueId] = useState<string>('39');
  const [team1Query, setTeam1Query] = useState<string>('');
  const [team2Query, setTeam2Query] = useState<string>('');
  const [team1, setTeam1] = useState<TeamOption | null>(null);
  const [team2, setTeam2] = useState<TeamOption | null>(null);
  const team1Id = team1?.id?.toString() || '';
  const team2Id = team2?.id?.toString() || '';

  const { data: h2hData, isLoading } = useQuery({
    queryKey: ['h2h', team1Id, team2Id],
    queryFn: async () => {
      if (!team1Id || !team2Id) return null;
      const res = await fetch(`/api/football/h2h?team1=${team1Id}&team2=${team2Id}`);
      if (!res.ok) throw new Error('Failed to fetch H2H data');
      return res.json();
    },
    enabled: !!team1Id && !!team2Id,
    staleTime: 86400000, // 24 hours
  });

  const fixtures = h2hData || [];

  const calculateStats = () => {
    let team1Wins = 0, team2Wins = 0, draws = 0;
    
    fixtures.forEach((match: any) => {
      if (match.goals.home > match.goals.away) {
        if (match.teams.home.id.toString() === team1Id) team1Wins++;
        else team2Wins++;
      } else if (match.goals.away > match.goals.home) {
        if (match.teams.away.id.toString() === team1Id) team1Wins++;
        else team2Wins++;
      } else {
        draws++;
      }
    });

    return { team1Wins, team2Wins, draws };
  };

  const stats = calculateStats();

  return (
    <div className="max-w-6xl mx-auto space-y-8">
      <div className="text-center">
        <h1 className="text-2xl sm:text-3xl md:text-4xl font-bold font-readex mb-3 text-white">مقارنة الفريقين</h1>
        <p className="text-neutral-400 font-ibm text-sm sm:text-base">اختر الدوري ثم ابحث عن الفريقين لعرض السجل التاريخي بينهما</p>
      </div>

      <TeamPairSelector
        leagueId={leagueId}
        onLeagueChange={(nextLeagueId) => {
          setLeagueId(nextLeagueId);
          setTeam1(null);
          setTeam2(null);
          setTeam1Query('');
          setTeam2Query('');
        }}
        team1={team1}
        team2={team2}
        team1Query={team1Query}
        team2Query={team2Query}
        onTeam1QueryChange={(value) => {
          setTeam1(null);
          setTeam1Query(value);
        }}
        onTeam2QueryChange={(value) => {
          setTeam2(null);
          setTeam2Query(value);
        }}
        onTeam1Select={(selectedTeam) => {
          setTeam1(selectedTeam);
          setTeam1Query(selectedTeam.name);
        }}
        onTeam2Select={(selectedTeam) => {
          setTeam2(selectedTeam);
          setTeam2Query(selectedTeam.name);
        }}
        title="اختيار طرفي المواجهة"
        description="استخدم نفس مسار الاختيار الموجود في مقارنة الفرق، لكن ركّز هنا على التاريخ المباشر بين الناديين."
      />

      {/* Stats Summary */}
      {team1 && team2 && (
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-5 sm:p-8">
          <h2 className="text-xl sm:text-2xl font-bold font-readex mb-5 border-r-4 border-nor-green pr-3">الإحصائيات</h2>

          {isLoading ? (
            <div className="grid grid-cols-3 gap-3">
              {[1, 2, 3].map((i) => (
                <div key={i} className="bg-neutral-800/50 rounded-lg h-20 animate-pulse" />
              ))}
            </div>
          ) : (
            <div className="grid grid-cols-3 gap-2 sm:gap-4">
              <div className="bg-nor-green/10 border border-nor-green/30 rounded-xl p-3 sm:p-6 text-center">
                <p className="text-[11px] sm:text-sm text-neutral-400 font-readex mb-1 sm:mb-2 truncate">{team1.name}</p>
                <p className="text-3xl sm:text-4xl font-bold text-nor-green">{stats.team1Wins}</p>
              </div>
              <div className="bg-neutral-800/50 border border-neutral-700 rounded-xl p-3 sm:p-6 text-center">
                <p className="text-[11px] sm:text-sm text-neutral-400 font-readex mb-1 sm:mb-2">تعادلات</p>
                <p className="text-3xl sm:text-4xl font-bold text-white">{stats.draws}</p>
              </div>
              <div className="bg-red-500/10 border border-red-500/30 rounded-xl p-3 sm:p-6 text-center">
                <p className="text-[11px] sm:text-sm text-neutral-400 font-readex mb-1 sm:mb-2 truncate">{team2.name}</p>
                <p className="text-3xl sm:text-4xl font-bold text-red-400">{stats.team2Wins}</p>
              </div>
            </div>
          )}

          <div className="mt-6 flex flex-wrap gap-3">
            <Link
              href="/compare/teams"
              className="rounded-full border border-neutral-700 bg-neutral-950 px-4 py-2 text-sm font-readex text-white hover:border-nor-green hover:text-nor-green transition-colors"
            >
              فتح المقارنة الموسمية
            </Link>
            <p className="text-sm text-neutral-500 font-ibm self-center">
              هذه الصفحة تركّز على سجل المواجهات المباشرة فقط، بينما صفحة المقارنة تعرض مؤشرات الموسم أيضاً.
            </p>
          </div>
        </div>
      )}

      {/* Matches History */}
      {team1 && team2 && (
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-5 sm:p-8">
          <h2 className="text-xl sm:text-2xl font-bold font-readex mb-5 border-r-4 border-nor-green pr-3">السجل التاريخي</h2>

          {isLoading ? (
            <div className="space-y-3">
              {[1, 2, 3].map((i) => (
                <div key={i} className="bg-neutral-800/50 rounded-lg h-16 animate-pulse" />
              ))}
            </div>
          ) : fixtures.length > 0 ? (
            <div className="space-y-2">
              {fixtures.map((match: any) => (
                <Link
                  key={match.fixture.id}
                  href={`/matches/${match.fixture.id}`}
                  className="flex items-center gap-2 p-3 sm:p-4 bg-neutral-800/30 hover:bg-neutral-800/50 border border-neutral-800 rounded-xl transition-colors group"
                >
                  <span className="text-[10px] sm:text-xs text-neutral-500 font-readex shrink-0 w-16 sm:w-24">
                    {new Date(match.fixture.date).toLocaleDateString('ar-EG')}
                  </span>

                  <div className="flex items-center gap-1.5 flex-1 min-w-0">
                    <img src={match.teams.home.logo} alt="" className="w-4 h-4 object-contain shrink-0" />
                    <span className="truncate text-xs sm:text-sm font-ibm">{match.teams.home.name}</span>
                  </div>

                  <div className="shrink-0 px-2 sm:px-4">
                    <span className="text-sm sm:text-lg font-bold text-nor-green font-readex whitespace-nowrap">
                      {match.goals.home} - {match.goals.away}
                    </span>
                  </div>

                  <div className="flex items-center gap-1.5 flex-1 justify-end min-w-0">
                    <span className="truncate text-xs sm:text-sm font-ibm text-right">{match.teams.away.name}</span>
                    <img src={match.teams.away.logo} alt="" className="w-4 h-4 object-contain shrink-0" />
                  </div>
                </Link>
              ))}
            </div>
          ) : (
            <div className="bg-neutral-800/30 border border-neutral-800 rounded-lg p-12 text-center">
              <p className="text-neutral-500 font-readex">لا توجد مباريات سابقة بين هذين الفريقين</p>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
