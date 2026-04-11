"use client";
import { useQuery } from '@tanstack/react-query';
import { useSearchParams } from 'next/navigation';
import { Suspense, useEffect, useMemo, useState } from 'react';
import StandingsTable from '@/components/matches/StandingsTable';
import MatchCard from '@/components/matches/MatchCard';
import LeagueSwitcher from '@/components/ui/LeagueSwitcher';
import { getLeagueMap } from '@/lib/config/leagues';
import { format } from 'date-fns';
import { isFinishedMatch, isLiveMatch, isUpcomingMatch } from '@/lib/fixtures';

function MatchesContent() {
  const searchParams = useSearchParams();
  const leagueId = searchParams.get('league') || 'all';
  const leagueData = leagueId === 'all' ? null : getLeagueMap(leagueId);
  const [selectedDate, setSelectedDate] = useState('');
  const [todayStr, setTodayStr] = useState('');
  useEffect(() => {
    const t = format(new Date(), 'yyyy-MM-dd');
    setSelectedDate(t);
    setTodayStr(t);
  }, []);
  const [statusFilter, setStatusFilter] = useState<'all' | 'live' | 'upcoming' | 'finished'>('all');

  const { data: matches, isLoading, isError, refetch } = useQuery({
    queryKey: ['daily-fixtures', selectedDate, leagueId],
    queryFn: async () => {
      const params = new URLSearchParams({ date: selectedDate });
      if (leagueId !== 'all') params.set('league', leagueId);
      const res = await fetch(`/api/football/fixtures?${params.toString()}`);
      if (!res.ok) throw new Error('Failed to fetch');
      return res.json();
    },
    enabled: !!selectedDate,
    staleTime: 15000,
  });

  const filteredMatches = useMemo(() => {
    const allMatches = matches || [];
    return allMatches.filter((match: any) => {
      if (statusFilter === 'live') return isLiveMatch(match);
      if (statusFilter === 'upcoming') return isUpcomingMatch(match);
      if (statusFilter === 'finished') return isFinishedMatch(match);
      return true;
    });
  }, [matches, statusFilter]);

  const summary = {
    total: matches?.length || 0,
    live: (matches || []).filter((match: any) => isLiveMatch(match)).length,
    upcoming: (matches || []).filter((match: any) => isUpcomingMatch(match)).length,
    finished: (matches || []).filter((match: any) => isFinishedMatch(match)).length,
  };

  return (
    <div className="w-full">
      <LeagueSwitcher allowAll defaultLeague="all" allLabel="كل البطولات" />
      <div className="mb-6 space-y-3">
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-4 flex items-center gap-3">
          <label className="text-sm text-neutral-400 font-readex shrink-0">التاريخ:</label>
          <input
            type="date"
            value={selectedDate}
            onChange={(e) => setSelectedDate(e.target.value)}
            className="flex-1 rounded-xl border border-neutral-700 bg-neutral-800 px-3 py-2 text-white font-ibm text-sm focus:outline-none focus:border-nor-green"
          />
        </div>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 sm:gap-3">
          {[
            { id: 'all', label: 'الكل', value: summary.total, color: 'text-white' },
            { id: 'live', label: 'مباشر', value: summary.live, color: 'text-nor-green' },
            { id: 'upcoming', label: 'قادمة', value: summary.upcoming, color: 'text-blue-400' },
            { id: 'finished', label: 'منتهية', value: summary.finished, color: 'text-neutral-300' },
          ].map((item) => (
            <button
              key={item.id}
              onClick={() => setStatusFilter(item.id as 'all' | 'live' | 'upcoming' | 'finished')}
              className={`rounded-2xl border p-3 sm:p-4 text-right transition-colors ${statusFilter === item.id ? 'border-nor-green bg-nor-green/10' : 'border-neutral-800 bg-neutral-900 hover:border-neutral-700'}`}
            >
              <p className="text-xs sm:text-sm text-neutral-500 font-readex">{item.label}</p>
              <p className={`mt-1.5 text-2xl sm:text-3xl font-bold font-readex ${item.color}`}>{item.value}</p>
            </button>
          ))}
        </div>
      </div>
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
        {/* Right Column: Today's Matches */}
        <div className="lg:col-span-8 space-y-6">
          <h1 className="text-xl sm:text-2xl md:text-3xl font-bold font-readex border-r-4 border-nor-green pr-4 mb-6">
            {leagueId === 'all' ? 'مباريات اليوم عبر كل البطولات' : `مباريات ${leagueData?.name || 'اليوم'}`} 
            <span className="block mt-2 text-sm font-ibm text-neutral-500 font-normal">
              {todayStr && selectedDate === todayStr ? 'تاريخ اليوم' : selectedDate}
            </span>
          </h1>
          
          {isLoading ? (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {[1, 2, 3, 4].map((i) => (
                <div key={i} className="bg-neutral-900 border border-neutral-800 rounded-2xl h-32 animate-pulse" />
              ))}
            </div>
          ) : isError ? (
            <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-8 text-center">
              <p className="text-neutral-400 font-readex">تعذر تحميل المباريات حالياً</p>
              <button
                onClick={() => refetch()}
                className="mt-4 px-4 py-2 rounded-full border border-neutral-700 text-sm font-readex hover:border-nor-green hover:text-nor-green transition-colors"
              >
                إعادة المحاولة
              </button>
            </div>
          ) : filteredMatches.length > 0 ? (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
               {filteredMatches.map((match: any) => (
                 <MatchCard key={match.fixture.id} match={match} />
               ))}
            </div>
          ) : (
            <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6 text-center text-neutral-500 font-readex">
              لا توجد مباريات مطابقة للفلاتر الحالية
            </div>
          )}
        </div>

        {/* Left Column: Standings */}
        <div className="lg:col-span-4 space-y-6">
          {leagueId === 'all' ? (
            <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6 space-y-3">
              <h2 className="text-2xl font-bold font-readex border-r-4 border-nor-green pr-4">اختر بطولة للترتيب</h2>
              <p className="text-sm text-neutral-500 font-ibm leading-7">
                صفحة المباريات تعرض الآن كل مباريات اليوم من البطولات المدعومة. اختر بطولة من الشريط أعلاه إذا أردت مشاهدة جدول الترتيب الخاص بها بجانب المباريات.
              </p>
            </div>
          ) : (
            <>
              <h2 className="text-2xl font-bold font-readex border-r-4 border-nor-green pr-4 mb-6">ترتيب {leagueData?.name}</h2>
              <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-4">
                <StandingsTable leagueId={leagueId} />
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

export default function MatchesPage() {
  return (
    <Suspense fallback={<div className="animate-pulse bg-neutral-900 h-96 rounded-2xl w-full"></div>}>
      <MatchesContent />
    </Suspense>
  )
}
