"use client";
import { useQuery } from '@tanstack/react-query';
import { useState, useEffect } from 'react';
import { format } from 'date-fns';
import Link from 'next/link';

export default function OddsPage() {
  const [selectedFixture, setSelectedFixture] = useState<string | null>(null);
  const [today, setToday] = useState('');
  useEffect(() => { setToday(format(new Date(), 'yyyy-MM-dd')); }, []);

  // Fetch today's fixtures (NS = not started)
  const { data: todayFixtures, isLoading: fixturesLoading } = useQuery({
    queryKey: ['fixtures-for-odds', today],
    queryFn: async () => {
      const res = await fetch(`/api/football/fixtures?date=${today}`);
      if (!res.ok) throw new Error('Failed to fetch fixtures');
      return res.json();
    },
    enabled: !!today,
    staleTime: 300000, // 5 min
  });

  const { data: odds, isLoading: oddsLoading } = useQuery({
    queryKey: ['odds', selectedFixture],
    queryFn: async () => {
      if (!selectedFixture) return null;
      const res = await fetch(`/api/football/odds?fixture=${selectedFixture}`);
      if (!res.ok) throw new Error('Failed to fetch odds');
      return res.json();
    },
    enabled: !!selectedFixture,
    staleTime: 300000,
  });

  const upcomingMatches = (Array.isArray(todayFixtures) ? todayFixtures : [])
    .filter((m: any) => m.fixture.status.short === 'NS');

  const selectedMatch = Array.isArray(todayFixtures)
    ? todayFixtures.find((m: any) => m.fixture.id.toString() === selectedFixture)
    : null;

  // Safely extract 1X2 market values from the odds response
  const extractOdds = (oddsData: any[]) => {
    return oddsData
      .map((bookmaker: any) => {
        const market = (bookmaker.bets || []).find(
          (b: any) => b.name === 'Match Winner' || b.name === 'Home/Draw/Away'
        );
        if (!market?.values?.length) return null;
        const home = market.values.find((v: any) => v.value === 'Home');
        const draw = market.values.find((v: any) => v.value === 'Draw');
        const away = market.values.find((v: any) => v.value === 'Away');
        if (!home && !draw && !away) return null;
        return {
          bookmaker: bookmaker.bookmaker?.name || bookmaker.name || 'شركة',
          home: home?.odd ?? '-',
          draw: draw?.odd ?? '-',
          away: away?.odd ?? '-',
        };
      })
      .filter(Boolean);
  };

  const parsedOdds = odds && Array.isArray(odds) ? extractOdds(odds) : [];

  return (
    <div className="max-w-7xl mx-auto space-y-8">
      {/* Header */}
      <div className="text-center space-y-3">
        <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-nor-green/10 border border-nor-green/20 rounded-full text-nor-green text-sm font-readex">
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 2v20M2 12h20"/></svg>
          مباريات اليوم
        </div>
        <h1 className="text-2xl sm:text-3xl md:text-4xl font-bold font-readex text-white">احتمالات المباريات</h1>
        <p className="text-neutral-400 font-ibm text-sm sm:text-base max-w-xl mx-auto">
          اختر مباراة من القائمة لعرض احتمالات الفوز والتعادل من أكبر شركات المراهنات
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* ── Matches list ──────────────────────────────────────────────── */}
        <div className="lg:col-span-1 space-y-3">
          <h2 className="text-lg font-bold font-readex border-r-4 border-nor-green pr-3" suppressHydrationWarning>
            مباريات اليوم{today ? ` — ${new Date(today).toLocaleDateString('ar-EG', { weekday: 'long', day: 'numeric', month: 'long' })}` : ''}
          </h2>

          {fixturesLoading ? (
            <div className="space-y-3">
              {[1, 2, 3, 4].map((i) => (
                <div key={i} className="bg-neutral-900 border border-neutral-800 rounded-xl h-20 animate-pulse" />
              ))}
            </div>
          ) : upcomingMatches.length > 0 ? (
            <div className="space-y-2 max-h-[600px] overflow-y-auto pr-1">
              {upcomingMatches.map((match: any) => (
                <button
                  key={match.fixture.id}
                  onClick={() => setSelectedFixture(match.fixture.id.toString())}
                  className={`w-full text-right p-4 rounded-xl border transition-all ${
                    selectedFixture === match.fixture.id.toString()
                      ? 'bg-nor-green/10 border-nor-green shadow-[0_0_12px_rgba(0,255,133,0.15)]'
                      : 'bg-neutral-900 border-neutral-800 hover:border-neutral-600'
                  }`}
                >
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-[11px] text-neutral-500 font-readex">{match.league.name}</span>
                    <span className="text-[11px] text-nor-green font-bold font-readex">
                      {new Date(match.fixture.date).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })}
                    </span>
                  </div>
                  <div className="flex items-center gap-2 text-sm font-ibm mb-1">
                    <img src={match.teams.home.logo} alt="" className="w-5 h-5 object-contain shrink-0" />
                    <span className="truncate text-white">{match.teams.home.name}</span>
                  </div>
                  <div className="flex items-center gap-2 text-sm font-ibm text-neutral-400">
                    <img src={match.teams.away.logo} alt="" className="w-5 h-5 object-contain shrink-0" />
                    <span className="truncate">{match.teams.away.name}</span>
                  </div>
                </button>
              ))}
            </div>
          ) : (
            <div className="bg-neutral-900 border border-neutral-800 rounded-xl p-8 text-center space-y-2">
              <p className="text-neutral-400 font-readex">لا توجد مباريات قادمة اليوم</p>
              <Link href="/matches" className="text-nor-green text-sm font-readex hover:underline">
                عرض جدول المباريات الكامل
              </Link>
            </div>
          )}
        </div>

        {/* ── Odds panel ───────────────────────────────────────────────── */}
        <div className="lg:col-span-2">
          {selectedMatch ? (
            <div className="space-y-5">
              {/* Match header */}
              <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6">
                <p className="text-xs text-neutral-500 font-readex text-center mb-4">{selectedMatch.league.name}</p>
                <div className="flex items-center justify-between gap-4">
                  <div className="flex flex-col items-center gap-2 flex-1">
                    <img src={selectedMatch.teams.home.logo} alt="" className="w-14 h-14 object-contain" />
                    <p className="font-bold font-readex text-center text-sm leading-tight">{selectedMatch.teams.home.name}</p>
                  </div>
                  <div className="text-center shrink-0 space-y-1">
                    <p className="text-2xl font-black font-readex text-nor-green">VS</p>
                    <p className="text-xs text-neutral-500 font-ibm">
                      {new Date(selectedMatch.fixture.date).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })}
                    </p>
                  </div>
                  <div className="flex flex-col items-center gap-2 flex-1">
                    <img src={selectedMatch.teams.away.logo} alt="" className="w-14 h-14 object-contain" />
                    <p className="font-bold font-readex text-center text-sm leading-tight">{selectedMatch.teams.away.name}</p>
                  </div>
                </div>
              </div>

              {/* Odds grid */}
              {oddsLoading ? (
                <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6 h-44 animate-pulse" />
              ) : parsedOdds.length > 0 ? (
                <div className="space-y-3">
                  {/* Column headers */}
                  <div className="grid grid-cols-4 gap-2 px-1 text-center text-[11px] sm:text-xs font-readex text-neutral-500">
                    <span className="text-right">الشركة</span>
                    <span className="truncate">{selectedMatch.teams.home.name.split(' ')[0]}</span>
                    <span>تعادل</span>
                    <span className="truncate">{selectedMatch.teams.away.name.split(' ')[0]}</span>
                  </div>
                  {parsedOdds.map((o: any, i: number) => (
                    <div key={i} className="bg-neutral-900 border border-neutral-800 rounded-xl p-3 sm:p-4 grid grid-cols-4 gap-2 items-center">
                      <p className="text-xs sm:text-sm font-readex font-bold text-nor-green truncate">{o.bookmaker}</p>
                      <div className="bg-neutral-800/60 rounded-lg p-2 sm:p-3 text-center">
                        <p className="text-base sm:text-xl font-bold font-ibm text-white">{o.home}</p>
                      </div>
                      <div className="bg-neutral-800/60 rounded-lg p-2 sm:p-3 text-center">
                        <p className="text-base sm:text-xl font-bold font-ibm text-neutral-300">{o.draw}</p>
                      </div>
                      <div className="bg-neutral-800/60 rounded-lg p-2 sm:p-3 text-center">
                        <p className="text-base sm:text-xl font-bold font-ibm text-white">{o.away}</p>
                      </div>
                    </div>
                  ))}
                  <p className="text-xs text-neutral-600 font-ibm text-center pt-1">
                    * الاحتمالات للأغراض الإعلامية فقط. لا تشجع نور على المراهنة.
                  </p>
                </div>
              ) : (
                <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-12 text-center">
                  <p className="text-neutral-400 font-readex mb-2">لا توجد احتمالات متاحة لهذه المباراة</p>
                  <p className="text-neutral-600 text-sm font-ibm">قد تُنشر الاحتمالات قريباً من وقت الانطلاق</p>
                </div>
              )}
            </div>
          ) : (
            <div className="h-full min-h-[320px] bg-neutral-900 border border-neutral-800 rounded-2xl flex flex-col items-center justify-center text-center p-12 gap-3">
              <div className="w-14 h-14 rounded-full bg-neutral-800 flex items-center justify-center mb-2">
                <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#525252" strokeWidth="1.5"><circle cx="12" cy="12" r="10"/><path d="M12 8v4l3 3"/></svg>
              </div>
              <p className="text-neutral-300 font-readex text-lg">اختر مباراة لعرض الاحتمالات</p>
              <p className="text-neutral-600 font-ibm text-sm">سيتم عرض أفضل الاحتمالات من جميع الشركات المتاحة</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
