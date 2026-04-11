"use client";
import { useQuery } from '@tanstack/react-query';
import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import LeagueSwitcher from '@/components/ui/LeagueSwitcher';
import { useSearchParams } from 'next/navigation';
import { Suspense } from 'react';
import { getLeagueMap } from '@/lib/config/leagues';

function TransfersContent() {
  const searchParams = useSearchParams();
  const leagueId = searchParams.get('league') || '39';
  const leagueData = getLeagueMap(leagueId);
  const [filterType, setFilterType] = useState<'all' | 'in' | 'out'>('all');
  const [selectedTeamId, setSelectedTeamId] = useState('');

  const { data: standingsData, isLoading: teamsLoading } = useQuery({
    queryKey: ['transfer-teams', leagueId],
    queryFn: async () => {
      const res = await fetch(`/api/football/standings?league=${leagueId}`);
      if (!res.ok) throw new Error('Failed to fetch teams');
      return res.json();
    },
    staleTime: 1800000,
  });

  const teams = useMemo(
    () =>
      (standingsData?.[0]?.league?.standings?.[0] || []).map((entry: any) => ({
        id: String(entry.team.id),
        name: entry.team.name,
        logo: entry.team.logo,
      })),
    [standingsData]
  );

  useEffect(() => {
    if (!teams.length) {
      setSelectedTeamId('');
      return;
    }

    setSelectedTeamId((current) =>
      current && teams.some((team: any) => team.id === current) ? current : teams[0].id
    );
  }, [teams]);

  const { data: transfers, isLoading, isError, refetch } = useQuery({
    queryKey: ['transfers', leagueId, selectedTeamId],
    queryFn: async () => {
      const params = new URLSearchParams();
      if (selectedTeamId) params.set('team', selectedTeamId);
      const res = await fetch(`/api/football/transfers?${params.toString()}`);
      if (!res.ok) throw new Error('Failed to fetch transfers');
      return res.json();
    },
    staleTime: 3600000, // 1 hour
    enabled: !!selectedTeamId,
  });

  const normalizedTransfers = (transfers || []).map((player: any) => ({
    ...player,
    transfers: (player.transfers || []).sort((a: any, b: any) => {
      const aDate = a.date ? new Date(a.date).getTime() : 0;
      const bDate = b.date ? new Date(b.date).getTime() : 0;
      return bDate - aDate;
    }),
  }));

  const filteredTransfers = normalizedTransfers.filter((t: any) => {
    const matchesType =
      filterType === 'all' ||
      t.transfers?.some((tr: any) => tr.type === filterType);
    return matchesType;
  });

  const incomingCount = normalizedTransfers.filter((player: any) =>
    player.transfers?.some((transfer: any) => transfer.type === 'in')
  ).length;
  const outgoingCount = normalizedTransfers.filter((player: any) =>
    player.transfers?.some((transfer: any) => transfer.type === 'out')
  ).length;
  const transferMovesCount = normalizedTransfers.reduce((sum: number, player: any) => sum + (player.transfers?.length || 0), 0);
  const selectedTeam = teams.find((team: any) => team.id === selectedTeamId);

  return (
    <div className="max-w-6xl mx-auto space-y-8">
      <div className="text-center">
        <h1 className="text-2xl sm:text-3xl md:text-4xl font-bold font-readex mb-3 text-white">سوق الانتقالات</h1>
        <p className="text-neutral-400 font-ibm text-sm sm:text-base">اختر البطولة ثم النادي لمراجعة القادمين والمغادرين بشكل واضح</p>
      </div>

      <LeagueSwitcher />

      <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-4">
          <p className="text-xs sm:text-sm text-neutral-500 font-readex">إجمالي اللاعبين</p>
          <p className="mt-1.5 text-2xl sm:text-3xl font-bold font-readex text-white">{normalizedTransfers.length}</p>
        </div>
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-4">
          <p className="text-xs sm:text-sm text-neutral-500 font-readex">الوافدون</p>
          <p className="mt-1.5 text-2xl sm:text-3xl font-bold font-readex text-nor-green">{incomingCount}</p>
        </div>
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-4">
          <p className="text-xs sm:text-sm text-neutral-500 font-readex">المغادرون</p>
          <p className="mt-1.5 text-2xl sm:text-3xl font-bold font-readex text-red-400">{outgoingCount}</p>
        </div>
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-4 col-span-2 sm:col-span-3">
          <p className="text-xs sm:text-sm text-neutral-500 font-readex">إجمالي الحركات المسجلة</p>
          <p className="mt-1.5 text-2xl sm:text-3xl font-bold font-readex text-white">{transferMovesCount}</p>
        </div>
      </div>

      <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-5 space-y-4">
        <div className="grid gap-4 lg:grid-cols-[1.4fr_1fr]">
          <div>
            <label className="block text-sm font-readex text-neutral-400 mb-3">النادي داخل {leagueData.name}</label>
            <div className="relative">
              <select
                value={selectedTeamId}
                onChange={(e) => setSelectedTeamId(e.target.value)}
                disabled={teamsLoading || teams.length === 0}
                className="w-full appearance-none rounded-xl border border-neutral-700 bg-neutral-800 px-4 py-3 text-white font-ibm focus:outline-none focus:border-nor-green disabled:opacity-60"
              >
                {teams.length === 0 ? (
                  <option value="">لا توجد فرق متاحة حالياً</option>
                ) : (
                  teams.map((team: any) => (
                    <option key={team.id} value={team.id}>
                      {team.name}
                    </option>
                  ))
                )}
              </select>
              <div className="pointer-events-none absolute inset-y-0 left-4 flex items-center text-neutral-500">
                <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="m6 9 6 6 6-6" />
                </svg>
              </div>
            </div>
            <p className="mt-3 text-xs text-neutral-500 font-ibm">
              يتم عرض انتقالات النادي المحدد فقط، مع نفس بيانات الـ API ولكن بصيغة أوضح وأسهل للتصفح.
            </p>
          </div>
          <div className="rounded-2xl border border-neutral-800 bg-neutral-800/30 p-4">
            <p className="text-sm text-neutral-500 font-readex">النادي المحدد</p>
            <div className="mt-3 flex items-center gap-3">
              {selectedTeam?.logo ? <img src={selectedTeam.logo} alt={selectedTeam.name} className="w-10 h-10 object-contain" /> : null}
              <div>
                <p className="font-readex font-bold text-white">{selectedTeam?.name || 'اختر نادياً'}</p>
                <p className="text-xs text-neutral-500 font-ibm">{leagueData.name}</p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div className="flex gap-3 justify-center flex-wrap">
        {(['all', 'in', 'out'] as const).map((type) => (
          <button
            key={type}
            onClick={() => setFilterType(type)}
            className={`px-6 py-2 rounded-full font-readex text-sm transition-all ${
              filterType === type
                ? 'bg-nor-green text-black font-bold'
                : 'bg-neutral-900 border border-neutral-800 text-neutral-300 hover:text-white'
            }`}
          >
            {type === 'all' ? 'الكل' : type === 'in' ? 'الوافدون' : 'المغادرون'}
          </button>
        ))}
      </div>

      {isLoading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="bg-neutral-900 border border-neutral-800 rounded-2xl h-32 animate-pulse" />
          ))}
        </div>
      ) : isError ? (
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-12 text-center">
          <p className="text-neutral-400 font-readex text-lg">تعذر تحميل بيانات الانتقالات حالياً</p>
          <button
            onClick={() => refetch()}
            className="mt-4 px-4 py-2 rounded-full border border-neutral-700 text-sm font-readex hover:border-nor-green hover:text-nor-green transition-colors"
          >
            إعادة المحاولة
          </button>
        </div>
      ) : filteredTransfers.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {filteredTransfers.map((player: any) => (
            <div key={player.player_id} className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6 hover:border-nor-green/50 transition-all">
              <div className="flex items-start gap-4">
                <img
                  src={player.player_photo}
                  alt={player.player_name}
                  className="w-16 h-16 rounded-full object-cover border border-neutral-700"
                />
                <div className="flex-1">
                  <Link href={`/players/${player.player_id}`} className="text-lg font-bold font-readex hover:text-nor-green transition-colors">
                    {player.player_name}
                  </Link>
                  <p className="text-sm text-neutral-400 font-ibm">{player.player_position}</p>
                </div>
              </div>

              <div className="mt-4 space-y-3">
                {player.transfers?.map((transfer: any, idx: number) => (
                  <div key={idx} className="flex items-center gap-3 text-sm font-ibm">
                    <span className={`px-2 py-1 rounded text-xs font-bold ${
                      transfer.type === 'in' ? 'bg-nor-green/20 text-nor-green' : 'bg-red-500/20 text-red-400'
                    }`}>
                      {transfer.type === 'in' ? 'وافد' : 'مغادر'}
                    </span>
                    <div className="flex-1">
                      <p className="text-white">
                        {transfer.type === 'in' ? 'من' : 'إلى'}: <span className="font-bold">{transfer.type === 'in' ? transfer.from?.name : transfer.to?.name}</span>
                      </p>
                      <p className="text-neutral-500 text-xs">
                        {transfer.type === 'in' ? 'النادي الحالي' : 'الوجهة'}: {transfer.type === 'in' ? transfer.to?.name : transfer.from?.name}
                      </p>
                      <p className="text-neutral-400 text-xs">
                        {transfer.date ? new Date(transfer.date).toLocaleDateString('ar-EG') : 'تاريخ غير محدد'}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-12 text-center">
          <p className="text-neutral-500 font-readex text-lg">لا توجد انتقالات مسجلة لهذا النادي حالياً</p>
          <p className="text-neutral-600 font-ibm text-sm mt-2">جرّب اختيار نادٍ آخر داخل {leagueData.name}</p>
        </div>
      )}
    </div>
  );
}

export default function TransfersPage() {
  return (
    <Suspense fallback={<div className="bg-neutral-900 border border-neutral-800 rounded-2xl h-96 animate-pulse" />}>
      <TransfersContent />
    </Suspense>
  );
}
