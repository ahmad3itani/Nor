"use client";

import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';
import MatchCard from '@/components/matches/MatchCard';
import { useFavorites } from '@/hooks/useFavorites';

type LiveFilter = 'all' | 'favorites' | 'high-scoring';

export default function LivePage() {
  const [filter, setFilter] = useState<LiveFilter>('all');
  const { favorites } = useFavorites();

  const { data: matches, isLoading, isError, refetch, dataUpdatedAt } = useQuery({
    queryKey: ['live-matches'],
    queryFn: async () => {
      const res = await fetch('/api/football/live');
      if (!res.ok) throw new Error('Failed to fetch live matches');
      return res.json();
    },
    refetchInterval: 30000,
    staleTime: 15000,
  });

  const favoriteTeamIds = useMemo(() => new Set(favorites.teams.map((team) => Number(team.id))), [favorites.teams]);

  const sortedMatches = useMemo(() => {
    const liveMatches = Array.isArray(matches) ? matches : [];

    const decorated = liveMatches.map((match: any) => {
      const hasFavoriteTeam =
        favoriteTeamIds.has(match.teams.home.id) || favoriteTeamIds.has(match.teams.away.id);
      const totalGoals = (match.goals.home ?? 0) + (match.goals.away ?? 0);

      return {
        match,
        hasFavoriteTeam,
        totalGoals,
      };
    });

    const filtered = decorated.filter((entry) => {
      if (filter === 'favorites') return entry.hasFavoriteTeam;
      if (filter === 'high-scoring') return entry.totalGoals >= 3;
      return true;
    });

    return filtered.sort((a, b) => {
      if (a.hasFavoriteTeam !== b.hasFavoriteTeam) return a.hasFavoriteTeam ? -1 : 1;
      return (b.match.fixture.status.elapsed || 0) - (a.match.fixture.status.elapsed || 0);
    });
  }, [matches, favoriteTeamIds, filter]);

  const summary = useMemo(() => {
    const liveMatches = Array.isArray(matches) ? matches : [];
    return {
      total: liveMatches.length,
      favorite: liveMatches.filter((match: any) =>
        favoriteTeamIds.has(match.teams.home.id) || favoriteTeamIds.has(match.teams.away.id)
      ).length,
      goals: liveMatches.reduce((sum: number, match: any) => sum + (match.goals.home ?? 0) + (match.goals.away ?? 0), 0),
      leagues: new Set(liveMatches.map((match: any) => match.league.id)).size,
    };
  }, [matches, favoriteTeamIds]);

  return (
    <div className="max-w-7xl mx-auto space-y-8">
      <div className="text-center space-y-4">
        <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-red-500/10 border border-red-500/20 rounded-full text-red-400 text-sm font-readex">
          <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse"></span>
          مركز المباريات المباشرة
        </div>
        <h1 className="text-2xl sm:text-3xl md:text-4xl font-bold font-readex text-white">تابع كل ما يحدث الآن</h1>
        <p className="text-neutral-400 font-ibm text-sm sm:text-base max-w-3xl mx-auto">
          نتائج مباشرة، ترتيب للمباريات حسب فرقك المفضلة، وتحديث تلقائي كل 30 ثانية.
        </p>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-4">
          <p className="text-xs sm:text-sm text-neutral-500 font-readex">مباشر الآن</p>
          <p className="mt-1.5 text-3xl font-bold font-readex text-white">{summary.total}</p>
        </div>
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-4">
          <p className="text-xs sm:text-sm text-neutral-500 font-readex">فرقك المفضلة</p>
          <p className="mt-1.5 text-3xl font-bold font-readex text-nor-green">{summary.favorite}</p>
        </div>
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-4">
          <p className="text-xs sm:text-sm text-neutral-500 font-readex">إجمالي الأهداف</p>
          <p className="mt-1.5 text-3xl font-bold font-readex text-yellow-400">{summary.goals}</p>
        </div>
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-4">
          <p className="text-xs sm:text-sm text-neutral-500 font-readex">البطولات النشطة</p>
          <p className="mt-1.5 text-3xl font-bold font-readex text-blue-400">{summary.leagues}</p>
        </div>
      </div>

      <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex gap-2 overflow-x-auto pb-0.5">
          {[
            { id: 'all', label: 'الكل' },
            { id: 'favorites', label: 'المفضلة' },
            { id: 'high-scoring', label: 'غزيرة الأهداف' },
          ].map((item) => (
            <button
              key={item.id}
              onClick={() => setFilter(item.id as LiveFilter)}
              className={`shrink-0 px-4 py-2 rounded-full text-sm font-readex transition-colors ${
                filter === item.id ? 'bg-nor-green text-black font-bold' : 'bg-neutral-800 text-neutral-300 hover:text-white'
              }`}
            >
              {item.label}
            </button>
          ))}
        </div>

        <div className="flex items-center gap-2 text-xs sm:text-sm text-neutral-500 font-ibm">
          <span className="hidden sm:inline" suppressHydrationWarning>آخر تحديث: {new Date(dataUpdatedAt || Date.now()).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })}</span>
          <button
            onClick={() => refetch()}
            className="px-3 py-1.5 rounded-full border border-neutral-700 text-neutral-300 hover:border-nor-green hover:text-nor-green transition-colors font-readex text-xs sm:text-sm"
          >
            تحديث
          </button>
        </div>
      </div>

      {isLoading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {[1, 2, 3, 4, 5, 6].map((item) => (
            <div key={item} className="bg-neutral-900 border border-neutral-800 rounded-2xl h-36 animate-pulse" />
          ))}
        </div>
      ) : isError ? (
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-12 text-center">
          <p className="text-neutral-300 font-readex text-lg">تعذر تحميل المباريات المباشرة حالياً</p>
          <button
            onClick={() => refetch()}
            className="mt-4 px-4 py-2 rounded-full border border-neutral-700 text-sm font-readex hover:border-nor-green hover:text-nor-green transition-colors"
          >
            إعادة المحاولة
          </button>
        </div>
      ) : sortedMatches.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {sortedMatches.map(({ match, hasFavoriteTeam, totalGoals }: any) => (
            <div key={match.fixture.id} className="space-y-2">
              <div className="flex items-center justify-between px-2">
                <div className="flex items-center gap-2 text-xs font-readex">
                  {hasFavoriteTeam && (
                    <span className="px-2 py-1 rounded-full bg-nor-green/10 text-nor-green border border-nor-green/20">مفضل</span>
                  )}
                  {totalGoals >= 3 && (
                    <span className="px-2 py-1 rounded-full bg-yellow-500/10 text-yellow-400 border border-yellow-500/20">مفتوحة</span>
                  )}
                </div>
                <Link href={`/matches/${match.fixture.id}`} className="text-xs text-neutral-500 hover:text-white transition-colors font-readex">
                  تفاصيل المباراة
                </Link>
              </div>
              <MatchCard match={match} />
            </div>
          ))}
        </div>
      ) : (
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-12 text-center">
          <p className="text-neutral-300 font-readex text-lg">لا توجد مباريات مطابقة لهذا الفلتر الآن</p>
          <p className="mt-2 text-sm text-neutral-500 font-ibm">يمكنك حفظ فرقك المفضلة ثم العودة لمشاهدتها أولاً هنا.</p>
        </div>
      )}
    </div>
  );
}
