"use client";

import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';
import PlayerSearchInput from '@/components/ui/PlayerSearchInput';
import dynamic from 'next/dynamic';
const PlayerComparisonRadar = dynamic(() => import('@/components/analytics/PlayerComparisonRadar'), { ssr: false, loading: () => <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 h-80 animate-pulse" /> });

type SelectedPlayer = {
  id: number;
  name: string;
  photo: string;
  age?: number;
  nationality?: string;
  teamName?: string | null;
  teamLogo?: string | null;
};

function normalizePlayerStats(payload: any) {
  const entry = payload?.[0];
  if (!entry) return null;

  const player = entry.player;
  const stat = entry.statistics?.[0];
  if (!player || !stat) return null;

  const rating = Math.min(10, Math.max(0, parseFloat(stat.games?.rating || '0') || 0));
  const goals = stat.goals?.total || 0;
  const assists = stat.goals?.assists || 0;
  const shots = stat.shots?.total || 0;
  const dribbles = stat.dribbles?.success || 0;
  const passAccuracy = Math.round((parseFloat(stat.passes?.accuracy || '0') || 0) / 10);

  return {
    id: player.id,
    name: player.name,
    photo: player.photo,
    teamName: stat.team?.name || null,
    teamLogo: stat.team?.logo || null,
    leagueName: stat.league?.name || null,
    stats: {
      appearances: stat.games?.appearences || 0,
      minutes: stat.games?.minutes || 0,
      goals,
      assists,
      shots,
      dribbles,
      passAccuracy: stat.passes?.accuracy || '0',
      rating: rating.toFixed(1),
      yellow: stat.cards?.yellow || 0,
      red: stat.cards?.red || 0,
    },
    radarStats: [goals, assists, passAccuracy, dribbles, rating, shots].map((value) => Math.min(10, Number(value) || 0)),
  };
}

export default function PlayerComparePage() {
  const [player1Query, setPlayer1Query] = useState('');
  const [player2Query, setPlayer2Query] = useState('');
  const [player1, setPlayer1] = useState<SelectedPlayer | null>(null);
  const [player2, setPlayer2] = useState<SelectedPlayer | null>(null);

  const { data: player1Data, isLoading: player1Loading } = useQuery({
    queryKey: ['player-compare', player1?.id],
    queryFn: async () => {
      const res = await fetch(`/api/football/player/${player1?.id}`);
      if (!res.ok) throw new Error('Failed to fetch player');
      return res.json();
    },
    enabled: !!player1?.id,
    staleTime: 300000,
  });

  const { data: player2Data, isLoading: player2Loading } = useQuery({
    queryKey: ['player-compare', player2?.id],
    queryFn: async () => {
      const res = await fetch(`/api/football/player/${player2?.id}`);
      if (!res.ok) throw new Error('Failed to fetch player');
      return res.json();
    },
    enabled: !!player2?.id,
    staleTime: 300000,
  });

  const stats1 = useMemo(() => normalizePlayerStats(player1Data), [player1Data]);
  const stats2 = useMemo(() => normalizePlayerStats(player2Data), [player2Data]);

  const comparisonRows = [
    { label: 'المباريات', getValue: (item: any) => item?.stats.appearances ?? 0 },
    { label: 'الدقائق', getValue: (item: any) => item?.stats.minutes ?? 0 },
    { label: 'الأهداف', getValue: (item: any) => item?.stats.goals ?? 0 },
    { label: 'الصناعة', getValue: (item: any) => item?.stats.assists ?? 0 },
    { label: 'التسديدات', getValue: (item: any) => item?.stats.shots ?? 0 },
    { label: 'المراوغات', getValue: (item: any) => item?.stats.dribbles ?? 0 },
    { label: 'دقة التمرير', getValue: (item: any) => item?.stats.passAccuracy ?? '0' },
    { label: 'التقييم', getValue: (item: any) => item?.stats.rating ?? '0.0' },
    { label: 'بطاقات صفراء', getValue: (item: any) => item?.stats.yellow ?? 0 },
    { label: 'بطاقات حمراء', getValue: (item: any) => item?.stats.red ?? 0 },
  ];

  return (
    <div className="max-w-7xl mx-auto space-y-10">
      <div className="text-center space-y-4">
        <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-nor-green/10 border border-nor-green/20 rounded-full text-nor-green text-sm font-readex">
          مقارنة اللاعبين
        </div>
        <h1 className="text-2xl sm:text-3xl md:text-4xl font-bold font-readex text-white">من الأفضل هذا الموسم؟</h1>
        <p className="text-neutral-400 font-ibm text-sm sm:text-base max-w-3xl mx-auto">
          اختر لاعبين وقارن بين أرقامهما بسرعة عبر الرادار والمؤشرات الأساسية.
        </p>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6">
          <PlayerSearchInput
            label="اللاعب الأول"
            value={player1 ? player1.name : player1Query}
            selectedPlayer={player1}
            onQueryChange={(value) => {
              setPlayer1(null);
              setPlayer1Query(value);
            }}
            onSelect={(selectedPlayer) => {
              setPlayer1(selectedPlayer);
              setPlayer1Query(selectedPlayer.name);
            }}
            excludePlayerId={player2?.id || null}
          />
        </div>

        <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6">
          <PlayerSearchInput
            label="اللاعب الثاني"
            value={player2 ? player2.name : player2Query}
            selectedPlayer={player2}
            onQueryChange={(value) => {
              setPlayer2(null);
              setPlayer2Query(value);
            }}
            onSelect={(selectedPlayer) => {
              setPlayer2(selectedPlayer);
              setPlayer2Query(selectedPlayer.name);
            }}
            excludePlayerId={player1?.id || null}
          />
        </div>
      </div>

      {(player1Loading || player2Loading) && (
        <div className="grid gap-4 md:grid-cols-2">
          {[1, 2].map((item) => (
            <div key={item} className="bg-neutral-900 border border-neutral-800 rounded-3xl h-64 animate-pulse" />
          ))}
        </div>
      )}

      {stats1 && stats2 ? (
        <>
          <div className="grid gap-6 grid-cols-1 lg:grid-cols-[1fr_380px]">
            <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6">
              <div className="grid gap-4 md:grid-cols-2">
                {[stats1, stats2].map((playerStats, index) => (
                  <div key={playerStats.id} className="rounded-2xl border border-neutral-800 bg-neutral-800/20 p-5">
                    <div className="flex items-center gap-3">
                      <img src={playerStats.photo} alt={playerStats.name} className="w-12 h-12 sm:w-16 sm:h-16 rounded-full object-cover border border-neutral-700 shrink-0" />
                      <div className="min-w-0">
                        <p className="truncate text-lg sm:text-2xl font-bold font-readex text-white">{playerStats.name}</p>
                        <p className="truncate text-sm text-neutral-500 font-ibm">
                          {playerStats.teamName || 'نادي غير متاح'}{playerStats.leagueName ? ` • ${playerStats.leagueName}` : ''}
                        </p>
                      </div>
                    </div>
                    <div className="mt-4 flex gap-2">
                      <Link href={`/players/${playerStats.id}`} className="px-4 py-2 rounded-full bg-neutral-900 border border-neutral-700 text-sm font-readex hover:border-nor-green hover:text-nor-green transition-colors">
                        ملف اللاعب
                      </Link>
                      {playerStats.teamName ? (
                        <span className={`px-4 py-2 rounded-full text-sm font-readex ${index === 0 ? 'bg-nor-green/10 text-nor-green' : 'bg-white/10 text-white'}`}>
                          {index === 0 ? 'اللاعب الأول' : 'اللاعب الثاني'}
                        </span>
                      ) : null}
                    </div>
                  </div>
                ))}
              </div>

              <div className="mt-6 overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-neutral-800 text-neutral-500 font-readex text-xs">
                      <th className="pb-3 text-center">{stats1.name}</th>
                      <th className="pb-3 text-center">المؤشر</th>
                      <th className="pb-3 text-center">{stats2.name}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {comparisonRows.map((row) => (
                      <tr key={row.label} className="border-b border-neutral-800/50">
                        <td className="py-3 text-center font-ibm text-white">{row.getValue(stats1)}</td>
                        <td className="py-3 text-center font-readex text-neutral-400">{row.label}</td>
                        <td className="py-3 text-center font-ibm text-white">{row.getValue(stats2)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>

            <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 flex flex-col">
              <h2 className="text-2xl font-bold font-readex mb-6 border-r-4 border-nor-green pr-4">الرادار المقارن</h2>
              <PlayerComparisonRadar
                player1={{ name: stats1.name, stats: stats1.radarStats, color: '#00FF85' }}
                player2={{ name: stats2.name, stats: stats2.radarStats, color: '#FFFFFF' }}
              />
              <p className="mt-4 text-xs text-neutral-500 font-ibm text-center">
                المقارنة مبنية على الأهداف، الصناعة، الدقة، المراوغات، التقييم، والتسديدات.
              </p>
            </div>
          </div>
        </>
      ) : (
        <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-12 text-center">
          <p className="text-neutral-300 font-readex text-lg">اختر لاعبين لبدء المقارنة</p>
          <p className="mt-2 text-sm text-neutral-500 font-ibm">
            يمكنك البحث باسم اللاعب مباشرة ومقارنة أرقامه في الموسم الحالي.
          </p>
        </div>
      )}
    </div>
  );
}
