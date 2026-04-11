"use client";
import { useQuery } from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import NewsCard from './NewsCard';

export default function NewsFeed() {
  const itemsPerPage = 10;
  const [page, setPage] = useState(1);
  const [query, setQuery] = useState('');
  const [searchTerm, setSearchTerm] = useState('');
  const [source, setSource] = useState('');

  useEffect(() => {
    const timeout = setTimeout(() => {
      setSearchTerm(query.trim());
      setPage(1);
    }, 300);

    return () => clearTimeout(timeout);
  }, [query]);

  useEffect(() => {
    setPage(1);
  }, [source]);

  const { data, isLoading, isFetching, isError, refetch } = useQuery({
    queryKey: ['news', page, searchTerm, source],
    queryFn: async () => {
      const params = new URLSearchParams({
        limit: String(page * itemsPerPage),
        offset: '0',
      });

      if (searchTerm) params.set('q', searchTerm);
      if (source) params.set('source', source);

      const res = await fetch(`/api/news?${params.toString()}`);
      if (!res.ok) throw new Error('Failed to fetch news');
      return res.json();
    },
    staleTime: 60000,
  });
  const articles = data?.items || [];
  const total = data?.total || 0;
  const sources = data?.sources || [];
  const hasMore = data?.hasMore || false;

  if (isLoading) {
    return (
      <div className="space-y-4">
        {[1, 2, 3].map((n) => (
          <div key={n} className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6 h-48 animate-pulse"></div>
        ))}
      </div>
    );
  }

  if (isError) {
    return (
      <div className="text-center py-16 text-neutral-400 bg-neutral-900 rounded-2xl border border-neutral-800">
        <p className="font-readex text-lg">تعذر تحميل الأخبار حالياً.</p>
        <button
          onClick={() => refetch()}
          className="mt-4 px-4 py-2 rounded-full border border-neutral-700 text-sm font-readex hover:border-nor-green hover:text-nor-green transition-colors"
        >
          إعادة المحاولة
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-5">
      <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-5 space-y-4">
        <div className="grid gap-4 md:grid-cols-[1fr_auto] md:items-center">
          <div className="space-y-2">
            <label className="block text-sm text-neutral-400 font-readex">ابحث داخل الأخبار</label>
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="اسم لاعب، نادٍ، أو بطولة"
              className="w-full rounded-xl border border-neutral-700 bg-neutral-800 px-4 py-3 text-white font-ibm placeholder-neutral-500 focus:outline-none focus:border-nor-green"
            />
          </div>
          <div className="text-sm text-neutral-500 font-readex">
            {total} خبر
          </div>
        </div>

        {sources.length > 0 && (
          <div className="flex flex-wrap gap-2">
            <button
              onClick={() => setSource('')}
              className={`px-3 py-1.5 rounded-full text-xs font-readex transition-colors ${source === '' ? 'bg-nor-green text-black font-bold' : 'bg-neutral-800 text-neutral-300 hover:text-white'}`}
            >
              كل المصادر
            </button>
            {sources.map((entry: any) => (
              <button
                key={entry.source}
                onClick={() => setSource(entry.source)}
                className={`px-3 py-1.5 rounded-full text-xs font-readex transition-colors ${source === entry.source ? 'bg-nor-green text-black font-bold' : 'bg-neutral-800 text-neutral-300 hover:text-white'}`}
              >
                {entry.source}
              </button>
            ))}
          </div>
        )}
      </div>

      {articles.length === 0 ? (
        <div className="text-center py-20 text-neutral-500 bg-neutral-900 rounded-2xl border border-neutral-800">
          <p className="font-readex text-lg">لم يتم العثور على أخبار مطابقة.</p>
          <p className="font-ibm text-sm mt-2">جرّب تغيير عبارة البحث أو اختيار مصدر آخر.</p>
        </div>
      ) : (
        <>
          {/* First article shown as featured card */}
          {page === 1 && !searchTerm && !source && articles[0] && (
            <div className="animate-slide-in-right">
              <NewsCard article={articles[0]} featured={true} />
            </div>
          )}
          {articles.map((article: any, index: number) => {
            // Skip index 0 when showing featured
            if (page === 1 && !searchTerm && !source && index === 0) return null;
            return (
              <div key={article.id} className="animate-slide-in-right" style={{ animationDelay: `${index * 0.05}s` }}>
                <NewsCard article={article} />
              </div>
            );
          })}

          <div className="py-4 text-center">
            {isFetching && <p className="text-neutral-500 font-readex">جاري التحميل...</p>}
            {!isFetching && hasMore && (
              <button
                onClick={() => setPage((prev) => prev + 1)}
                className="px-5 py-2.5 rounded-full bg-neutral-900 border border-neutral-800 text-sm font-readex text-white hover:border-nor-green hover:text-nor-green transition-colors"
              >
                تحميل المزيد
              </button>
            )}
            {!hasMore && articles.length > 0 && (
              <p className="text-neutral-500 font-readex">وصلت إلى آخر الأخبار المتاحة</p>
            )}
          </div>
        </>
      )}
    </div>
  );
}
