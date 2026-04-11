"use client";

import Link from 'next/link';
import { useQuery } from '@tanstack/react-query';
import { useEffect, useState } from 'react';

type SearchResponse = {
  teams: Array<{ id: number; name: string; logo: string; country: string }>;
  players: Array<{ id: number; name: string; photo: string; age?: number; nationality?: string; teamName?: string | null; teamLogo?: string | null }>;
  news: Array<{ id: number; slug: string; title_ar: string; source: string; created_at: string }>;
};

export default function GlobalSearch() {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');

  useEffect(() => {
    const timeout = setTimeout(() => setDebouncedQuery(query.trim()), 250);
    return () => clearTimeout(timeout);
  }, [query]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        setOpen((prev) => !prev);
      }
      if (event.key === 'Escape') {
        setOpen(false);
      }
    };

    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, []);

  const { data, isFetching, isError } = useQuery<SearchResponse>({
    queryKey: ['global-search', debouncedQuery],
    queryFn: async () => {
      const res = await fetch(`/api/search?q=${encodeURIComponent(debouncedQuery)}`);
      if (!res.ok) throw new Error('Failed to search');
      return res.json();
    },
    enabled: open && debouncedQuery.length >= 2,
    staleTime: 120000,
  });

  const hasResults = Boolean((data?.teams.length || 0) + (data?.players.length || 0) + (data?.news.length || 0));

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="hidden md:flex items-center gap-3 rounded-full border border-neutral-800 bg-neutral-900/80 px-4 py-2 text-sm text-neutral-400 transition-colors hover:border-neutral-700 hover:text-white"
      >
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
        <span className="font-readex">ابحث في نور</span>
        <span className="rounded-md border border-neutral-700 px-1.5 py-0.5 text-[10px] text-neutral-500">Ctrl K</span>
      </button>

      <button
        onClick={() => setOpen(true)}
        className="text-neutral-400 hover:text-white transition-colors p-2"
        aria-label="Open search"
      >
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
      </button>

      {open && (
        <div className="fixed inset-0 z-[70] bg-black/70 backdrop-blur-sm px-4 py-8" onClick={() => setOpen(false)}>
          <div
            className="mx-auto max-w-3xl rounded-3xl border border-neutral-800 bg-[#0b0f0e] shadow-2xl"
            onClick={(event) => event.stopPropagation()}
          >
            <div className="flex items-center gap-3 border-b border-neutral-800 px-5 py-4">
              <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="text-neutral-500"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
              <input
                autoFocus
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="ابحث عن لاعب، فريق، أو خبر"
                className="w-full bg-transparent text-white font-ibm text-base outline-none placeholder:text-neutral-500"
              />
              <button
                onClick={() => setOpen(false)}
                className="rounded-full border border-neutral-800 px-3 py-1 text-xs font-readex text-neutral-400 hover:text-white"
              >
                إغلاق
              </button>
            </div>

            <div className="max-h-[70vh] overflow-y-auto p-5 space-y-6">
              {debouncedQuery.length < 2 ? (
                <div className="rounded-2xl border border-neutral-800 bg-neutral-900/40 p-6 text-center">
                  <p className="font-readex text-white">ابدأ بكتابة حرفين على الأقل</p>
                  <p className="mt-2 text-sm text-neutral-500 font-ibm">ستظهر لك نتائج موحدة من الفرق واللاعبين والأخبار</p>
                </div>
              ) : isFetching ? (
                <div className="rounded-2xl border border-neutral-800 bg-neutral-900/40 p-6 text-center text-neutral-500 font-readex">
                  جاري البحث...
                </div>
              ) : isError ? (
                <div className="rounded-2xl border border-neutral-800 bg-neutral-900/40 p-6 text-center text-neutral-400 font-readex">
                  تعذر تنفيذ البحث حالياً
                </div>
              ) : hasResults ? (
                <>
                  {data?.teams.length ? (
                    <section className="space-y-3">
                      <h3 className="text-sm font-readex text-neutral-500">الفرق</h3>
                      <div className="space-y-2">
                        {data.teams.map((team) => (
                          <Link
                            key={team.id}
                            href={`/teams/${team.id}`}
                            onClick={() => setOpen(false)}
                            className="flex items-center gap-3 rounded-2xl border border-neutral-800 bg-neutral-900/40 px-4 py-3 transition-colors hover:border-nor-green/40 hover:bg-neutral-900"
                          >
                            <img src={team.logo} alt={team.name} className="h-10 w-10 object-contain" />
                            <div>
                              <p className="font-readex font-bold text-white">{team.name}</p>
                              <p className="text-xs text-neutral-500 font-ibm">{team.country}</p>
                            </div>
                          </Link>
                        ))}
                      </div>
                    </section>
                  ) : null}

                  {data?.players.length ? (
                    <section className="space-y-3">
                      <h3 className="text-sm font-readex text-neutral-500">اللاعبون</h3>
                      <div className="space-y-2">
                        {data.players.map((player) => (
                          <Link
                            key={player.id}
                            href={`/players/${player.id}`}
                            onClick={() => setOpen(false)}
                            className="flex items-center gap-3 rounded-2xl border border-neutral-800 bg-neutral-900/40 px-4 py-3 transition-colors hover:border-nor-green/40 hover:bg-neutral-900"
                          >
                            <img src={player.photo} alt={player.name} className="h-10 w-10 rounded-full object-cover border border-neutral-700" />
                            <div className="min-w-0">
                              <p className="truncate font-readex font-bold text-white">{player.name}</p>
                              <p className="truncate text-xs text-neutral-500 font-ibm">
                                {player.teamName || player.nationality || 'لاعب كرة قدم'}
                              </p>
                            </div>
                          </Link>
                        ))}
                      </div>
                    </section>
                  ) : null}

                  {data?.news.length ? (
                    <section className="space-y-3">
                      <h3 className="text-sm font-readex text-neutral-500">الأخبار</h3>
                      <div className="space-y-2">
                        {data.news.map((article) => (
                          <Link
                            key={article.id}
                            href={`/news/${article.slug}`}
                            onClick={() => setOpen(false)}
                            className="block rounded-2xl border border-neutral-800 bg-neutral-900/40 px-4 py-3 transition-colors hover:border-nor-green/40 hover:bg-neutral-900"
                          >
                            <p className="font-amiri text-lg font-bold text-white line-clamp-2">{article.title_ar}</p>
                            <p className="mt-2 text-xs text-neutral-500 font-ibm">{article.source}</p>
                          </Link>
                        ))}
                      </div>
                    </section>
                  ) : null}
                </>
              ) : (
                <div className="rounded-2xl border border-neutral-800 bg-neutral-900/40 p-6 text-center">
                  <p className="font-readex text-white">لا توجد نتائج مطابقة</p>
                  <p className="mt-2 text-sm text-neutral-500 font-ibm">جرّب اسم لاعب أو فريق أو كلمة من خبر</p>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </>
  );
}
