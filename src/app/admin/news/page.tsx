"use client";

import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';
import { useState } from 'react';

export default function NewsAdminPage() {
  const [isRunning, setIsRunning] = useState(false);

  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ['admin-news-dashboard'],
    queryFn: async () => {
      const res = await fetch('/api/admin/news');
      if (!res.ok) throw new Error('Failed to load admin dashboard');
      return res.json();
    },
    staleTime: 30000,
  });

  const triggerPipeline = async () => {
    setIsRunning(true);
    try {
      const res = await fetch('/api/admin/news', { method: 'POST' });
      if (!res.ok) throw new Error('Failed to trigger pipeline');
      await refetch();
    } finally {
      setIsRunning(false);
    }
  };

  return (
    <div className="max-w-7xl mx-auto space-y-8">
      <div className="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div>
          <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-nor-green/10 border border-nor-green/20 rounded-full text-nor-green text-sm font-readex">
            <span className="w-2 h-2 rounded-full bg-nor-green"></span>
            لوحة إدارة الأخبار
          </div>
          <h1 className="mt-4 text-4xl font-bold font-readex text-white">تشغيل ومراقبة خط الأخبار</h1>
          <p className="mt-2 text-neutral-400 font-ibm">إحصاءات المحتوى، أداء المصادر، وتشغيل يدوي لخط إعادة الصياغة.</p>
        </div>

        <div className="flex gap-3">
          <button
            onClick={() => refetch()}
            className="px-4 py-2 rounded-full border border-neutral-700 text-sm font-readex text-neutral-300 hover:border-nor-green hover:text-nor-green transition-colors"
          >
            تحديث
          </button>
          <button
            onClick={triggerPipeline}
            disabled={isRunning}
            className="px-4 py-2 rounded-full bg-nor-green text-black text-sm font-readex font-bold disabled:opacity-60"
          >
            {isRunning ? 'جاري التشغيل...' : 'تشغيل خط الأخبار'}
          </button>
        </div>
      </div>

      {isLoading ? (
        <div className="grid gap-4 md:grid-cols-4">
          {[1, 2, 3, 4].map((item) => (
            <div key={item} className="bg-neutral-900 border border-neutral-800 rounded-2xl h-28 animate-pulse" />
          ))}
        </div>
      ) : isError ? (
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-12 text-center">
          <p className="text-neutral-300 font-readex text-lg">تعذر تحميل لوحة الأخبار حالياً</p>
        </div>
      ) : (
        <>
          <div className="grid gap-4 md:grid-cols-4">
            <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6">
              <p className="text-sm text-neutral-500 font-readex">إجمالي المقالات</p>
              <p className="mt-2 text-4xl font-bold font-readex text-white">{data.articleCount}</p>
            </div>
            <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6">
              <p className="text-sm text-neutral-500 font-readex">الروابط المرصودة</p>
              <p className="mt-2 text-4xl font-bold font-readex text-nor-green">{data.seenCount}</p>
            </div>
            <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6">
              <p className="text-sm text-neutral-500 font-readex">عدد المصادر</p>
              <p className="mt-2 text-4xl font-bold font-readex text-blue-400">{data.sourceStats.length}</p>
            </div>
            <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6">
              <p className="text-sm text-neutral-500 font-readex">آخر تشغيل</p>
              <p className="mt-2 text-lg font-bold font-readex text-white">
                {data.recentRuns[0]?.started_at
                  ? new Date(data.recentRuns[0].started_at).toLocaleString('ar-EG')
                  : 'لا يوجد'}
              </p>
            </div>
          </div>

          <div className="grid gap-8 lg:grid-cols-2">
            <section className="space-y-4">
              <h2 className="text-2xl font-bold font-readex border-r-4 border-nor-green pr-4">المصادر</h2>
              <div className="space-y-3">
                {data.sourceStats.map((source: any) => (
                  <div key={source.source} className="bg-neutral-900 border border-neutral-800 rounded-2xl p-4 flex items-center justify-between gap-4">
                    <div>
                      <p className="font-readex font-bold text-white">{source.source}</p>
                      <p className="text-xs text-neutral-500 font-ibm">
                        آخر مقال: {source.latest_created_at ? new Date(source.latest_created_at).toLocaleString('ar-EG') : 'غير متاح'}
                      </p>
                    </div>
                    <span className="text-2xl font-bold font-readex text-nor-green">{source.count}</span>
                  </div>
                ))}
              </div>
            </section>

            <section className="space-y-4">
              <h2 className="text-2xl font-bold font-readex border-r-4 border-nor-green pr-4">آخر التشغيلات</h2>
              <div className="space-y-3">
                {data.recentRuns.map((run: any) => (
                  <div key={run.id} className="bg-neutral-900 border border-neutral-800 rounded-2xl p-4">
                    <div className="flex items-center justify-between gap-4">
                      <p className="font-readex font-bold text-white">{run.pipeline_name}</p>
                      <span className={`px-2 py-1 rounded-full text-xs font-readex ${
                        run.status === 'completed'
                          ? 'bg-nor-green/10 text-nor-green'
                          : run.status === 'failed'
                            ? 'bg-red-500/10 text-red-400'
                            : 'bg-yellow-500/10 text-yellow-400'
                      }`}>
                        {run.status}
                      </span>
                    </div>
                    <p className="mt-2 text-sm text-neutral-500 font-ibm">
                      عناصر جديدة: {run.new_items_found} • محفوظ: {run.processed_count}
                    </p>
                    <p className="mt-1 text-xs text-neutral-600 font-ibm">
                      بدأ: {run.started_at ? new Date(run.started_at).toLocaleString('ar-EG') : '-'}
                    </p>
                    {run.error_message ? (
                      <p className="mt-2 text-xs text-red-400 font-ibm">{run.error_message}</p>
                    ) : null}
                  </div>
                ))}
              </div>
            </section>
          </div>

          <section className="space-y-4">
            <div className="flex items-center justify-between gap-4">
              <h2 className="text-2xl font-bold font-readex border-r-4 border-nor-green pr-4">آخر المقالات</h2>
              <Link href="/news" className="text-sm text-nor-green hover:underline font-readex">الواجهة العامة</Link>
            </div>
            <div className="space-y-3">
              {data.recentArticles.map((article: any) => (
                <Link
                  key={article.id}
                  href={`/news/${article.slug}`}
                  className="block bg-neutral-900 border border-neutral-800 rounded-2xl p-4 hover:border-nor-green/40 transition-colors"
                >
                  <div className="flex items-center justify-between gap-4">
                    <div className="min-w-0">
                      <p className="truncate font-amiri text-xl font-bold text-white">{article.title_ar}</p>
                      <p className="text-xs text-neutral-500 font-ibm">
                        {article.source} • {new Date(article.created_at).toLocaleString('ar-EG')}
                      </p>
                    </div>
                    <span className="text-sm text-nor-green font-readex">عرض</span>
                  </div>
                </Link>
              ))}
            </div>
          </section>
        </>
      )}
    </div>
  );
}
