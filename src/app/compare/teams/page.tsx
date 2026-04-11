"use client";

import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';
import TeamPairSelector from '@/components/teams/TeamPairSelector';
import { getLeagueMap } from '@/lib/config/leagues';

type SelectedTeam = {
  id: number;
  name: string;
  logo: string;
  country: string;
  founded?: number | null;
  venueName?: string | null;
};

function normalizeTeamSummary(payload: any, teamId: number, standings: any[]) {
  const details = payload?.details;
  const stats = payload?.stats;
  const team = details?.team;
  const venue = details?.venue;

  if (!team || !stats) return null;

  const standing = standings.find((entry: any) => entry?.team?.id === teamId) || null;

  return {
    id: team.id,
    name: team.name,
    logo: team.logo,
    country: team.country,
    founded: team.founded,
    venueName: venue?.name || null,
    venueCity: venue?.city || null,
    rank: standing?.rank || null,
    points: standing?.points || 0,
    form: standing?.form || stats.form || '-',
    recentFixtures: payload?.fixtures || [],
    metrics: {
      played: stats.fixtures?.played?.total || 0,
      wins: stats.fixtures?.wins?.total || 0,
      draws: stats.fixtures?.draws?.total || 0,
      losses: stats.fixtures?.loses?.total || 0,
      goalsFor: stats.goals?.for?.total?.total || 0,
      goalsAgainst: stats.goals?.against?.total?.total || 0,
      cleanSheets: stats.clean_sheet?.total || 0,
      failedToScore: stats.failed_to_score?.total || 0,
    },
  };
}

function TeamMetricRow({
  label,
  leftValue,
  rightValue,
}: {
  label: string;
  leftValue: number | string;
  rightValue: number | string;
}) {
  const leftNumeric = Number(leftValue);
  const rightNumeric = Number(rightValue);
  const hasNumericValues = Number.isFinite(leftNumeric) && Number.isFinite(rightNumeric);
  const leftBetter = hasNumericValues && leftNumeric > rightNumeric;
  const rightBetter = hasNumericValues && rightNumeric > leftNumeric;

  return (
    <tr className="border-b border-neutral-800/60">
      <td className={`py-3 text-center font-ibm ${leftBetter ? 'text-nor-green font-bold' : 'text-white'}`}>{leftValue}</td>
      <td className="py-3 text-center text-neutral-400 font-readex">{label}</td>
      <td className={`py-3 text-center font-ibm ${rightBetter ? 'text-nor-green font-bold' : 'text-white'}`}>{rightValue}</td>
    </tr>
  );
}

export default function TeamComparePage() {
  const [leagueId, setLeagueId] = useState('39');
  const [team1Query, setTeam1Query] = useState('');
  const [team2Query, setTeam2Query] = useState('');
  const [team1, setTeam1] = useState<SelectedTeam | null>(null);
  const [team2, setTeam2] = useState<SelectedTeam | null>(null);

  const leagueData = getLeagueMap(leagueId);

  const standingsQuery = useQuery({
    queryKey: ['team-compare-standings', leagueId],
    queryFn: async () => {
      const res = await fetch(`/api/football/standings?league=${leagueId}`);
      if (!res.ok) throw new Error('Failed to load standings');
      return res.json();
    },
    staleTime: 300000,
  });

  const standings = useMemo(
    () => standingsQuery.data?.[0]?.league?.standings?.[0] || [],
    [standingsQuery.data]
  );

  const team1QueryData = useQuery({
    queryKey: ['team-compare-summary', team1?.id, leagueId],
    queryFn: async () => {
      const res = await fetch(`/api/football/team/${team1?.id}/summary?league=${leagueId}`);
      if (!res.ok) throw new Error('Failed to load team summary');
      return res.json();
    },
    enabled: !!team1?.id,
    staleTime: 300000,
  });

  const team2QueryData = useQuery({
    queryKey: ['team-compare-summary', team2?.id, leagueId],
    queryFn: async () => {
      const res = await fetch(`/api/football/team/${team2?.id}/summary?league=${leagueId}`);
      if (!res.ok) throw new Error('Failed to load team summary');
      return res.json();
    },
    enabled: !!team2?.id,
    staleTime: 300000,
  });

  const h2hQuery = useQuery({
    queryKey: ['team-compare-h2h', team1?.id, team2?.id],
    queryFn: async () => {
      const res = await fetch(`/api/football/h2h?team1=${team1?.id}&team2=${team2?.id}`);
      if (!res.ok) throw new Error('Failed to load head to head');
      return res.json();
    },
    enabled: !!team1?.id && !!team2?.id,
    staleTime: 300000,
  });

  const team1Summary = useMemo(
    () => (team1 ? normalizeTeamSummary(team1QueryData.data, team1.id, standings) : null),
    [team1, team1QueryData.data, standings]
  );
  const team2Summary = useMemo(
    () => (team2 ? normalizeTeamSummary(team2QueryData.data, team2.id, standings) : null),
    [team2, team2QueryData.data, standings]
  );

  const recentMeetings = (h2hQuery.data || []).slice(0, 5);
  const isLoading = team1QueryData.isLoading || team2QueryData.isLoading || standingsQuery.isLoading;
  const hasError = team1QueryData.isError || team2QueryData.isError || standingsQuery.isError || h2hQuery.isError;

  return (
    <div className="max-w-7xl mx-auto space-y-10">
      <div className="text-center space-y-4">
        <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-nor-green/10 border border-nor-green/20 rounded-full text-nor-green text-sm font-readex">
          مقارنة الفرق
        </div>
        <h1 className="text-2xl sm:text-3xl md:text-4xl font-bold font-readex text-white">من يملك الموسم الأقوى؟</h1>
        <p className="text-neutral-400 font-ibm text-sm sm:text-base max-w-3xl mx-auto">
          اختر الدوري ثم قارن بين فريقين عبر ترتيب الموسم، النتائج، الدفاع والهجوم، وآخر المواجهات المباشرة.
        </p>
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
        title="اختيار طرفي المقارنة"
        description={`المقارنة الحالية داخل ${leagueData.name}، لذلك الترتيب والأداء يعكسان نفس الموسم ونفس البطولة.`}
      />

      {isLoading ? (
        <div className="grid gap-4 md:grid-cols-2">
          {[1, 2].map((card) => (
            <div key={card} className="h-64 rounded-3xl border border-neutral-800 bg-neutral-900 animate-pulse" />
          ))}
        </div>
      ) : null}

      {hasError ? (
        <div className="rounded-3xl border border-red-500/30 bg-red-500/10 p-6 text-center">
          <p className="text-red-200 font-readex">تعذر تحميل المقارنة حالياً. جرّب تغيير الدوري أو إعادة اختيار الفريقين.</p>
        </div>
      ) : null}

      {team1Summary && team2Summary ? (
        <>
          <div className="grid gap-6 grid-cols-1 xl:grid-cols-[1.3fr_0.7fr]">
            <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6">
              <div className="grid gap-4 md:grid-cols-2">
                {[team1Summary, team2Summary].map((teamSummary, index) => (
                  <div key={teamSummary.id} className="rounded-2xl border border-neutral-800 bg-neutral-800/20 p-5">
                    <div className="flex items-center gap-3">
                      <img src={teamSummary.logo} alt={teamSummary.name} className="h-12 w-12 sm:h-16 sm:w-16 object-contain shrink-0" />
                      <div className="min-w-0">
                        <p className="truncate text-lg sm:text-2xl font-bold font-readex text-white">{teamSummary.name}</p>
                        <p className="truncate text-sm text-neutral-500 font-ibm">
                          {teamSummary.country}
                          {teamSummary.venueName ? ` • ${teamSummary.venueName}` : ''}
                        </p>
                      </div>
                    </div>

                    <div className="mt-4 grid grid-cols-3 gap-3 text-center">
                      <div className="rounded-2xl border border-neutral-800 bg-neutral-950/50 p-3">
                        <p className="text-xs text-neutral-500 font-readex">الترتيب</p>
                        <p className="mt-1 text-xl font-bold font-ibm text-white">{teamSummary.rank || '-'}</p>
                      </div>
                      <div className="rounded-2xl border border-neutral-800 bg-neutral-950/50 p-3">
                        <p className="text-xs text-neutral-500 font-readex">النقاط</p>
                        <p className="mt-1 text-xl font-bold font-ibm text-white">{teamSummary.points}</p>
                      </div>
                      <div className="rounded-2xl border border-neutral-800 bg-neutral-950/50 p-3">
                        <p className="text-xs text-neutral-500 font-readex">الفورمة</p>
                        <p className={`mt-1 text-lg font-bold font-ibm ${index === 0 ? 'text-nor-green' : 'text-white'}`}>{teamSummary.form}</p>
                      </div>
                    </div>

                    <div className="mt-4 flex gap-2">
                      <Link href={`/teams/${teamSummary.id}`} className="rounded-full border border-neutral-700 bg-neutral-950 px-4 py-2 text-sm font-readex text-white hover:border-nor-green hover:text-nor-green transition-colors">
                        ملف الفريق
                      </Link>
                      <Link href="/h2h" className="rounded-full border border-neutral-700 bg-neutral-950 px-4 py-2 text-sm font-readex text-neutral-300 hover:border-white hover:text-white transition-colors">
                        مواجهات مباشرة
                      </Link>
                    </div>
                  </div>
                ))}
              </div>

              <div className="mt-6 overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-neutral-800 text-neutral-500 font-readex text-xs">
                      <th className="pb-3 text-center">{team1Summary.name}</th>
                      <th className="pb-3 text-center">المؤشر</th>
                      <th className="pb-3 text-center">{team2Summary.name}</th>
                    </tr>
                  </thead>
                  <tbody>
                    <TeamMetricRow label="الترتيب" leftValue={team1Summary.rank || '-'} rightValue={team2Summary.rank || '-'} />
                    <TeamMetricRow label="النقاط" leftValue={team1Summary.points} rightValue={team2Summary.points} />
                    <TeamMetricRow label="المباريات" leftValue={team1Summary.metrics.played} rightValue={team2Summary.metrics.played} />
                    <TeamMetricRow label="الانتصارات" leftValue={team1Summary.metrics.wins} rightValue={team2Summary.metrics.wins} />
                    <TeamMetricRow label="التعادلات" leftValue={team1Summary.metrics.draws} rightValue={team2Summary.metrics.draws} />
                    <TeamMetricRow label="الخسائر" leftValue={team1Summary.metrics.losses} rightValue={team2Summary.metrics.losses} />
                    <TeamMetricRow label="له" leftValue={team1Summary.metrics.goalsFor} rightValue={team2Summary.metrics.goalsFor} />
                    <TeamMetricRow label="عليه" leftValue={team1Summary.metrics.goalsAgainst} rightValue={team2Summary.metrics.goalsAgainst} />
                    <TeamMetricRow label="شباك نظيفة" leftValue={team1Summary.metrics.cleanSheets} rightValue={team2Summary.metrics.cleanSheets} />
                    <TeamMetricRow label="فشل هجومي" leftValue={team1Summary.metrics.failedToScore} rightValue={team2Summary.metrics.failedToScore} />
                  </tbody>
                </table>
              </div>
            </div>

            <div className="space-y-6">
              <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6">
                <h2 className="text-2xl font-bold font-readex mb-4 border-r-4 border-nor-green pr-4">آخر المواجهات</h2>
                <div className="space-y-3">
                  {recentMeetings.length > 0 ? (
                    recentMeetings.map((fixture: any) => (
                      <Link
                        key={fixture.fixture.id}
                        href={`/matches/${fixture.fixture.id}`}
                        className="block rounded-2xl border border-neutral-800 bg-neutral-950/50 p-4 hover:border-nor-green/40 transition-colors"
                      >
                        <p className="text-xs text-neutral-500 font-readex">
                          {fixture.league.name} • {new Date(fixture.fixture.date).toLocaleDateString('ar-EG', { month: 'short', day: 'numeric', year: 'numeric' })}
                        </p>
                        <div className="mt-2 flex items-center justify-between gap-3 text-sm font-ibm text-white">
                          <span className="truncate">{fixture.teams.home.name}</span>
                          <span className="shrink-0 rounded-full bg-neutral-800 px-3 py-1 font-bold text-nor-green">
                            {fixture.goals.home}-{fixture.goals.away}
                          </span>
                          <span className="truncate">{fixture.teams.away.name}</span>
                        </div>
                      </Link>
                    ))
                  ) : (
                    <p className="text-sm text-neutral-500 font-ibm">لا توجد مواجهات مباشرة متاحة حتى الآن بين هذين الفريقين.</p>
                  )}
                </div>
              </div>

              <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6">
                <h2 className="text-2xl font-bold font-readex mb-4 border-r-4 border-nor-green pr-4">قراءة سريعة</h2>
                <div className="space-y-3 text-sm font-ibm text-neutral-300">
                  <p>
                    يتقدم {team1Summary.points >= team2Summary.points ? team1Summary.name : team2Summary.name} في سباق النقاط داخل {leagueData.name}.
                  </p>
                  <p>
                    يملك {team1Summary.metrics.goalsFor >= team2Summary.metrics.goalsFor ? team1Summary.name : team2Summary.name} الهجوم الأقوى حتى الآن.
                  </p>
                  <p>
                    دفاعياً، {team1Summary.metrics.goalsAgainst <= team2Summary.metrics.goalsAgainst ? team1Summary.name : team2Summary.name} استقبل أهدافاً أقل هذا الموسم.
                  </p>
                </div>
              </div>
            </div>
          </div>
        </>
      ) : (
        <div className="rounded-3xl border border-dashed border-neutral-700 bg-neutral-900/60 p-8 text-center">
          <p className="text-white font-readex text-lg">اختر فريقين من نفس الدوري لبدء المقارنة المتقدمة.</p>
          <p className="text-neutral-500 font-ibm text-sm mt-2">ستظهر هنا أرقام الموسم وآخر المواجهات وروابط سريعة إلى ملفات الفرق والمباريات.</p>
        </div>
      )}
    </div>
  );
}
