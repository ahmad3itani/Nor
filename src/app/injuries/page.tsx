"use client";
import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';
import LeagueSwitcher from '@/components/ui/LeagueSwitcher';
import { useSearchParams } from 'next/navigation';
import { Suspense } from 'react';
import { useEffect, useMemo, useState } from 'react';
import { getLeagueMap } from '@/lib/config/leagues';

function InjuriesContent() {
  const searchParams = useSearchParams();
  const leagueId = searchParams.get('league') || '39';
  const [typeFilter, setTypeFilter] = useState<'all' | 'injury' | 'suspension'>('all');
  const [selectedTeamId, setSelectedTeamId] = useState('');
  const leagueData = getLeagueMap(leagueId);

  const { data: standingsData, isLoading: teamsLoading } = useQuery({
    queryKey: ['injuries-teams', leagueId],
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

  const { data: injuries, isLoading, isError, refetch } = useQuery({
    queryKey: ['injuries', leagueId, selectedTeamId],
    queryFn: async () => {
      const params = new URLSearchParams({ league: leagueId });
      if (selectedTeamId) params.set('team', selectedTeamId);
      const res = await fetch(`/api/football/injuries?${params.toString()}`);
      if (!res.ok) throw new Error('Failed to fetch injuries');
      return res.json();
    },
    staleTime: 1800000, // 30 minutes
    enabled: !!selectedTeamId,
  });

  const getSeverityColor = (severity: string) => {
    switch (severity?.toLowerCase()) {
      case 'out':
        return 'bg-red-500/20 text-red-400 border-red-500/30';
      case 'doubtful':
        return 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30';
      case 'questionable':
        return 'bg-orange-500/20 text-orange-400 border-orange-500/30';
      default:
        return 'bg-neutral-700/20 text-neutral-300 border-neutral-700/30';
    }
  };

  const normalizedInjuries = injuries || [];
  const filteredInjuries = normalizedInjuries.filter((injury: any) => {
    const type = (injury.type || '').toLowerCase();
    const matchesType =
      typeFilter === 'all' ||
      (typeFilter === 'injury' && type === 'injury') ||
      (typeFilter === 'suspension' && type === 'suspension');
    return matchesType;
  });

  const injuryCount = normalizedInjuries.filter((item: any) => item.type === 'Injury').length;
  const suspensionCount = normalizedInjuries.filter((item: any) => item.type === 'Suspension').length;
  const reasonCount = normalizedInjuries.filter((item: any) => Boolean(item.injury_reason)).length;
  const selectedTeam = teams.find((team: any) => team.id === selectedTeamId);

  return (
    <div className="max-w-6xl mx-auto space-y-8">
      <div className="text-center">
        <h1 className="text-2xl sm:text-3xl md:text-4xl font-bold font-readex mb-3 text-white">تقرير الإصابات</h1>
        <p className="text-neutral-400 font-ibm text-sm sm:text-base">اختر البطولة ثم النادي لعرض قائمة الإصابات والإيقافات الخاصة به</p>
      </div>

      <LeagueSwitcher />

      <div className="grid grid-cols-3 gap-3">
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-4">
          <p className="text-xs sm:text-sm text-neutral-500 font-readex">إصابات</p>
          <p className="mt-1.5 text-2xl sm:text-3xl font-bold font-readex text-red-400">{injuryCount}</p>
        </div>
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-4">
          <p className="text-xs sm:text-sm text-neutral-500 font-readex">إيقافات</p>
          <p className="mt-1.5 text-2xl sm:text-3xl font-bold font-readex text-yellow-400">{suspensionCount}</p>
        </div>
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-4">
          <p className="text-xs sm:text-sm text-neutral-500 font-readex">موصوفة</p>
          <p className="mt-1.5 text-2xl sm:text-3xl font-bold font-readex text-white">{reasonCount}</p>
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
              يتم جلب الإصابات مباشرة من واجهة الـ API حسب البطولة، ثم تصفيتها على النادي الذي تختاره.
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
        <div className="flex gap-2 flex-wrap">
          {[
            { id: 'all', label: 'الكل' },
            { id: 'injury', label: 'إصابات' },
            { id: 'suspension', label: 'إيقافات' },
          ].map((item) => (
            <button
              key={item.id}
              onClick={() => setTypeFilter(item.id as 'all' | 'injury' | 'suspension')}
              className={`px-4 py-2 rounded-full text-sm font-readex transition-colors ${typeFilter === item.id ? 'bg-nor-green text-black font-bold' : 'bg-neutral-800 text-neutral-300 hover:text-white'}`}
            >
              {item.label}
            </button>
          ))}
        </div>
      </div>

      {isLoading ? (
        <div className="space-y-4">
          {[1, 2, 3, 4, 5].map((i) => (
            <div key={i} className="bg-neutral-900 border border-neutral-800 rounded-2xl h-24 animate-pulse" />
          ))}
        </div>
      ) : isError ? (
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-12 text-center">
          <p className="text-neutral-400 font-readex text-lg">تعذر تحميل تقرير الإصابات حالياً</p>
          <button
            onClick={() => refetch()}
            className="mt-4 px-4 py-2 rounded-full border border-neutral-700 text-sm font-readex hover:border-nor-green hover:text-nor-green transition-colors"
          >
            إعادة المحاولة
          </button>
        </div>
      ) : filteredInjuries.length > 0 ? (
        <div className="space-y-4">
          {filteredInjuries.map((injury: any, idx: number) => (
            <div key={`injury-${injury.player_id}-${idx}`} className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6 hover:border-nor-green/50 transition-all">
              <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
                <div className="flex items-start gap-4 flex-1">
                  <img
                    src={injury.player_photo}
                    alt={injury.player_name}
                    className="w-14 h-14 rounded-full object-cover border border-neutral-700"
                  />
                  <div className="flex-1">
                    <Link href={`/players/${injury.player_id}`} className="text-lg font-bold font-readex hover:text-nor-green transition-colors">
                      {injury.player_name}
                    </Link>
                    <p className="text-sm text-neutral-400 font-ibm">{injury.team_name}</p>
                  </div>
                </div>

                <div className="flex flex-col md:flex-row gap-3 md:items-center">
                  <div className={`px-4 py-2 rounded-lg border font-readex text-sm font-bold ${getSeverityColor(injury.type)}`}>
                    {injury.type === 'Injury' ? 'إصابة' : injury.type === 'Suspension' ? 'إيقاف' : injury.type}
                  </div>
                  
                  {injury.fixture_date && (
                    <div className="bg-neutral-800/50 border border-neutral-700 rounded-lg px-4 py-2">
                      <p className="text-xs text-neutral-500 font-readex">تحديث الإصابة</p>
                      <p className="text-white font-bold font-ibm">{new Date(injury.fixture_date).toLocaleDateString('ar-EG')}</p>
                    </div>
                  )}
                </div>
              </div>

              {injury.injury_reason && (
                <p className="mt-4 text-sm text-neutral-400 font-ibm border-t border-neutral-800 pt-4">
                  <span className="text-neutral-500">السبب:</span> {injury.injury_reason}
                </p>
              )}
            </div>
          ))}
        </div>
      ) : (
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-12 text-center">
          <p className="text-neutral-500 font-readex text-lg">لا توجد إصابات أو إيقافات مسجلة لهذا النادي حالياً</p>
          <p className="text-neutral-600 font-ibm text-sm mt-2">جرّب اختيار نادٍ آخر داخل {leagueData.name}</p>
        </div>
      )}
    </div>
  );
}

export default function InjuriesPage() {
  return (
    <Suspense fallback={<div className="bg-neutral-900 border border-neutral-800 rounded-2xl h-96 animate-pulse" />}>
      <InjuriesContent />
    </Suspense>
  );
}
