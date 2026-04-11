"use client";

import { useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';
import { useFavorites } from '@/hooks/useFavorites';
import ReminderButton from '@/components/ui/ReminderButton';

export default function WatchlistPage() {
  const { favorites, ready } = useFavorites();
  const teamIds = useMemo(() => favorites.teams.map((team) => team.id).join(','), [favorites.teams]);

  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ['watchlist', teamIds],
    queryFn: async () => {
      const res = await fetch(`/api/football/watchlist?teamIds=${teamIds}`);
      if (!res.ok) throw new Error('Failed to fetch watchlist');
      return res.json();
    },
    enabled: ready && favorites.teams.length > 0,
    staleTime: 300000,
  });

  const items = Array.isArray(data) ? data : [];

  return (
    <div className="max-w-7xl mx-auto space-y-8">
      <div className="text-center space-y-4">
        <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-blue-500/10 border border-blue-500/20 rounded-full text-blue-400 text-sm font-readex">
          <span className="w-2 h-2 rounded-full bg-blue-400"></span>
          قائمة المتابعة
        </div>
        <h1 className="text-4xl sm:text-5xl font-bold font-readex text-white">مباريات فرقك القادمة</h1>
        <p className="text-neutral-400 font-ibm text-lg max-w-3xl mx-auto">
          نظرة سريعة على المباريات القادمة للفرق التي أضفتها إلى المفضلة.
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6">
          <p className="text-sm text-neutral-500 font-readex">الفرق المتابعة</p>
          <p className="mt-2 text-4xl font-bold font-readex text-white">{favorites.teams.length}</p>
        </div>
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6">
          <p className="text-sm text-neutral-500 font-readex">المباريات القادمة</p>
          <p className="mt-2 text-4xl font-bold font-readex text-nor-green">
            {items.reduce((sum: number, entry: any) => sum + (entry.fixtures?.length || 0), 0)}
          </p>
        </div>
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6">
          <p className="text-sm text-neutral-500 font-readex">الدخول السريع</p>
          <Link href="/favorites" className="mt-3 inline-block text-sm text-nor-green hover:underline font-readex">
            إدارة المفضلة
          </Link>
          <Link href="/reminders" className="mt-2 block text-sm text-nor-green hover:underline font-readex">
            فتح التنبيهات
          </Link>
        </div>
      </div>

      {!ready ? (
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl h-96 animate-pulse" />
      ) : favorites.teams.length === 0 ? (
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-12 text-center">
          <p className="text-neutral-300 font-readex text-lg">أضف فرقاً إلى المفضلة لتبدأ قائمة المتابعة</p>
          <p className="mt-2 text-sm text-neutral-500 font-ibm">يمكنك حفظ أي فريق من صفحة الفريق أو من نتائج البحث.</p>
        </div>
      ) : isLoading ? (
        <div className="grid gap-4 lg:grid-cols-2">
          {[1, 2, 3, 4].map((item) => (
            <div key={item} className="bg-neutral-900 border border-neutral-800 rounded-2xl h-48 animate-pulse" />
          ))}
        </div>
      ) : isError ? (
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-12 text-center">
          <p className="text-neutral-300 font-readex text-lg">تعذر تحميل قائمة المتابعة حالياً</p>
          <button
            onClick={() => refetch()}
            className="mt-4 px-4 py-2 rounded-full border border-neutral-700 text-sm font-readex hover:border-nor-green hover:text-nor-green transition-colors"
          >
            إعادة المحاولة
          </button>
        </div>
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          {items.map((entry: any) => {
            const team = favorites.teams.find((favorite) => favorite.id === entry.teamId);
            const fixtures = entry.fixtures || [];

            return (
              <div key={entry.teamId} className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6 space-y-4">
                <div className="flex items-center gap-3">
                  {team?.logo ? <img src={team.logo} alt={team.name} className="w-12 h-12 object-contain" /> : null}
                  <div className="min-w-0">
                    <h2 className="truncate text-2xl font-bold font-readex text-white">{team?.name || 'فريق مفضل'}</h2>
                    <p className="truncate text-sm text-neutral-500 font-ibm">{team?.country || 'مباريات قادمة'}</p>
                  </div>
                </div>

                {fixtures.length > 0 ? (
                  <div className="space-y-3">
                    {fixtures.map((fixture: any) => (
                      <div
                        key={fixture.fixture.id}
                        className="rounded-xl border border-neutral-800 bg-neutral-800/30 p-4 hover:border-nor-green/40 transition-colors"
                      >
                        <div className="flex items-center justify-between text-xs text-neutral-500 font-readex mb-3">
                          <span>{fixture.league.name}</span>
                          <span>
                            {new Date(fixture.fixture.date).toLocaleDateString('ar-EG', { month: 'short', day: 'numeric' })} •{' '}
                            {new Date(fixture.fixture.date).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })}
                          </span>
                        </div>
                        <Link href={`/matches/${fixture.fixture.id}`} className="flex items-center justify-between gap-3">
                          <div className="flex items-center gap-2 flex-1 min-w-0">
                            <img src={fixture.teams.home.logo} alt="" className="w-6 h-6 object-contain" />
                            <span className="truncate font-ibm text-white">{fixture.teams.home.name}</span>
                          </div>
                          <span className="text-nor-green font-readex text-sm shrink-0">ضد</span>
                          <div className="flex items-center gap-2 flex-1 min-w-0 justify-end">
                            <span className="truncate font-ibm text-white text-left" dir="ltr">{fixture.teams.away.name}</span>
                            <img src={fixture.teams.away.logo} alt="" className="w-6 h-6 object-contain" />
                          </div>
                        </Link>
                        <div className="mt-4 flex items-center justify-between gap-3">
                          <span className="text-xs text-neutral-500 font-ibm">تلقي تنبيه قبل المباراة بـ 15 دقيقة تقريباً</span>
                          <ReminderButton fixture={fixture} />
                        </div>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="rounded-xl border border-neutral-800 bg-neutral-800/20 p-6 text-center text-neutral-500 font-ibm">
                    لا توجد مباريات قادمة متاحة حالياً لهذا الفريق.
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
