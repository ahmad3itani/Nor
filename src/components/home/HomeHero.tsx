"use client";

import Link from 'next/link';
import { useQuery } from '@tanstack/react-query';

export default function HomeHero() {
  const { data: liveData } = useQuery({
    queryKey: ['live-matches-hero'],
    queryFn: async () => {
      const res = await fetch('/api/football/live');
      if (!res.ok) throw new Error('Failed');
      return res.json();
    },
    staleTime: 15000,
    refetchInterval: 30000,
  });

  const liveCount = Array.isArray(liveData) ? liveData.length : 0;
  const featuredLive = Array.isArray(liveData) ? liveData[0] : null;

  return (
    <section className="relative overflow-hidden rounded-3xl bg-[#080808] border border-neutral-800/60 min-h-[280px]">
      {/* Pitch lines background pattern */}
      <div className="absolute inset-0 pointer-events-none select-none opacity-[0.04]">
        <svg width="100%" height="100%" viewBox="0 0 800 320" preserveAspectRatio="xMidYMid slice" fill="none" xmlns="http://www.w3.org/2000/svg">
          <rect x="40" y="20" width="720" height="280" rx="4" stroke="white" strokeWidth="2"/>
          <line x1="400" y1="20" x2="400" y2="300" stroke="white" strokeWidth="2"/>
          <circle cx="400" cy="160" r="60" stroke="white" strokeWidth="2"/>
          <circle cx="400" cy="160" r="4" fill="white"/>
          <rect x="290" y="20" width="220" height="80" stroke="white" strokeWidth="2"/>
          <rect x="330" y="20" width="140" height="36" stroke="white" strokeWidth="2"/>
          <rect x="290" y="200" width="220" height="80" stroke="white" strokeWidth="2"/>
          <rect x="330" y="244" width="140" height="36" stroke="white" strokeWidth="2"/>
        </svg>
      </div>

      {/* Green glow top-right */}
      <div className="absolute top-0 left-0 w-80 h-80 bg-nor-green/8 blur-[100px] rounded-full pointer-events-none" />
      <div className="absolute bottom-0 right-0 w-60 h-60 bg-nor-green/5 blur-[80px] rounded-full pointer-events-none" />

      <div className="relative z-10 px-6 py-8 md:px-10 md:py-10 flex flex-col md:flex-row items-start md:items-center gap-8">
        {/* Left: Branding + tagline */}
        <div className="flex-1 space-y-4">
          <div className="flex items-center gap-2">
            <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-readex font-bold bg-nor-green/15 border border-nor-green/30 text-nor-green">
              {liveCount > 0 ? (
                <>
                  <span className="w-1.5 h-1.5 rounded-full bg-nor-green animate-pulse" />
                  {liveCount} مباراة مباشرة الآن
                </>
              ) : (
                <>
                  <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg>
                  تحديث مستمر لحظة بلحظة
                </>
              )}
            </span>
          </div>

          <div>
            <h1 className="text-2xl sm:text-3xl md:text-4xl lg:text-5xl font-black font-readex text-white leading-tight">
              كل ما يخص
              <br />
              <span className="text-nor-green">كرة القدم</span>
              {' '}في مكان واحد
            </h1>
            <p className="mt-3 text-neutral-400 font-ibm text-sm sm:text-base max-w-md leading-relaxed">
              أخبار حصرية، نتائج مباشرة، إحصائيات عميقة، ترتيب الدوريات — مدعوم بالذكاء الاصطناعي
            </p>
          </div>

          <div className="flex flex-wrap gap-2 pt-1">
            <Link
              href="/live"
              className="flex items-center gap-2 px-4 py-2 sm:px-5 sm:py-2.5 bg-nor-green text-black font-bold font-readex text-sm rounded-full hover:bg-nor-green/90 transition-all shadow-[0_0_20px_rgba(0,255,133,0.25)]"
            >
              <span className="w-1.5 h-1.5 rounded-full bg-black animate-pulse" />
              مباشر الآن
            </Link>
            <Link
              href="/matches"
              className="flex items-center gap-2 px-4 py-2 sm:px-5 sm:py-2.5 bg-neutral-800 text-white font-readex text-sm rounded-full border border-neutral-700 hover:border-neutral-500 transition-all"
            >
              المباريات
            </Link>
            <Link
              href="/news"
              className="flex items-center gap-2 px-4 py-2 sm:px-5 sm:py-2.5 bg-neutral-800 text-white font-readex text-sm rounded-full border border-neutral-700 hover:border-neutral-500 transition-all"
            >
              الأخبار
            </Link>
          </div>
        </div>

        {/* Right: Live match card or stats grid */}
        <div className="w-full md:w-auto md:min-w-[260px] space-y-3">
          {featuredLive ? (
            <Link
              href="/live"
              className="block bg-neutral-900/90 border border-red-500/30 rounded-2xl p-5 hover:border-red-500/50 transition-all group"
            >
              <div className="flex items-center gap-2 mb-3">
                <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse" />
                <span className="text-xs font-readex text-red-400 font-bold">جارٍ الآن</span>
                <span className="text-xs font-ibm text-neutral-500 mr-auto">
                  {featuredLive.league?.name}
                </span>
              </div>
              <div className="flex items-center justify-between gap-4">
                <div className="flex flex-col items-center gap-1.5 flex-1">
                  <img src={featuredLive.teams?.home?.logo} alt="" className="w-10 h-10 object-contain" />
                  <p className="text-xs font-readex font-bold text-white text-center leading-tight">{featuredLive.teams?.home?.name}</p>
                </div>
                <div className="flex flex-col items-center shrink-0">
                  <p className="text-3xl font-black font-ibm text-white">
                    {featuredLive.goals?.home ?? 0} – {featuredLive.goals?.away ?? 0}
                  </p>
                  <span className="text-[10px] text-red-400 font-readex font-bold mt-0.5">{featuredLive.fixture?.status?.elapsed}'</span>
                </div>
                <div className="flex flex-col items-center gap-1.5 flex-1">
                  <img src={featuredLive.teams?.away?.logo} alt="" className="w-10 h-10 object-contain" />
                  <p className="text-xs font-readex font-bold text-white text-center leading-tight">{featuredLive.teams?.away?.name}</p>
                </div>
              </div>
            </Link>
          ) : (
            <div className="grid grid-cols-2 gap-3">
              {[
                { label: 'الأخبار', value: 'حصري', href: '/news', icon: '📰', color: 'text-blue-400', border: 'border-blue-500/20', bg: 'bg-blue-500/5' },
                { label: 'التحليلات', value: 'عمق', href: '/analytics', icon: '📊', color: 'text-purple-400', border: 'border-purple-500/20', bg: 'bg-purple-500/5' },
                { label: 'الانتقالات', value: 'لحظي', href: '/transfers', icon: '🔄', color: 'text-amber-400', border: 'border-amber-500/20', bg: 'bg-amber-500/5' },
                { label: 'الإصابات', value: 'محدّث', href: '/injuries', icon: '🏥', color: 'text-red-400', border: 'border-red-500/20', bg: 'bg-red-500/5' },
              ].map((item) => (
                <Link
                  key={item.href}
                  href={item.href}
                  className={`rounded-2xl border ${item.border} ${item.bg} p-4 hover:border-neutral-600 transition-all`}
                >
                  <p className="text-xl mb-1">{item.icon}</p>
                  <p className={`text-xs font-readex font-bold ${item.color}`}>{item.value}</p>
                  <p className="text-xs text-white font-ibm mt-0.5">{item.label}</p>
                </Link>
              ))}
            </div>
          )}
        </div>
      </div>
    </section>
  );
}
