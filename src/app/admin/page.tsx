'use client';

import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';
import { useState } from 'react';

export default function AdminDashboard() {
  const [pipelineLog, setPipelineLog] = useState<string | null>(null);
  const [running, setRunning] = useState(false);

  const { data, isLoading, refetch } = useQuery({
    queryKey: ['admin-dashboard'],
    queryFn: async () => {
      const [articles, pipeline] = await Promise.all([
        fetch('/api/admin/articles?limit=5').then(r => r.json()),
        fetch('/api/admin/news').then(r => r.json()),
      ]);
      return { articles, pipeline };
    },
    staleTime: 15000,
  });

  const triggerPipeline = async () => {
    setRunning(true);
    setPipelineLog('جاري تشغيل الخط...');
    try {
      const res = await fetch('/api/admin/news', { method: 'POST' });
      const json = await res.json();
      setPipelineLog(
        res.ok
          ? `✅ اكتمل — عناصر جديدة: ${json.result?.newItemsFound ?? 0}، محفوظ: ${json.result?.processedCount ?? 0}`
          : `❌ فشل: ${json.error}`
      );
      refetch();
    } catch (e: any) {
      setPipelineLog(`❌ ${e.message}`);
    } finally {
      setRunning(false);
    }
  };

  const stats = [
    { label: 'إجمالي المقالات', value: data?.pipeline?.articleCount ?? '—', color: 'text-white' },
    { label: 'مصادر RSS', value: data?.pipeline?.sourceStats?.length ?? '—', color: 'text-nor-green' },
    { label: 'روابط مرصودة', value: data?.pipeline?.seenCount ?? '—', color: 'text-blue-400' },
    { label: 'آخر تشغيل', value: data?.pipeline?.recentRuns?.[0]?.started_at
        ? new Date(data.pipeline.recentRuns[0].started_at).toLocaleString('ar-EG', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
        : '—', color: 'text-yellow-400' },
  ];

  return (
    <div className="space-y-8 max-w-5xl">
      {/* Stats */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {stats.map(s => (
          <div key={s.label} className="bg-neutral-900 border border-neutral-800 rounded-2xl p-5">
            <p className="text-xs text-neutral-500 font-readex mb-1">{s.label}</p>
            {isLoading
              ? <div className="h-8 w-16 bg-neutral-800 rounded animate-pulse mt-1" />
              : <p className={`text-3xl font-bold font-readex ${s.color}`}>{s.value}</p>
            }
          </div>
        ))}
      </div>

      {/* Pipeline control */}
      <section className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6 space-y-4">
        <div className="flex items-center justify-between gap-4">
          <div>
            <h2 className="font-readex font-bold text-white">خط نشر الأخبار</h2>
            <p className="text-xs text-neutral-500 font-readex mt-0.5">
              يعمل تلقائياً كل 10 دقائق عبر Vercel Cron • يجلب من {7} مصادر RSS • يعيد الصياغة بالذكاء الاصطناعي
            </p>
          </div>
          <button
            onClick={triggerPipeline}
            disabled={running}
            className="flex-shrink-0 px-5 py-2 rounded-full bg-nor-green text-black text-sm font-readex font-bold disabled:opacity-60 hover:bg-nor-green/90 transition-colors"
          >
            {running ? 'جاري...' : 'تشغيل الآن'}
          </button>
        </div>
        {pipelineLog && (
          <p className="text-sm font-readex bg-neutral-800 rounded-lg px-4 py-2 text-neutral-200">{pipelineLog}</p>
        )}

        {/* Recent runs */}
        {(data?.pipeline?.recentRuns?.length ?? 0) > 0 && (
          <div className="space-y-2 pt-2">
            {(data?.pipeline?.recentRuns ?? []).slice(0, 5).map((run: any) => (
              <div key={run.id} className="flex items-center gap-3 text-sm font-readex">
                <span className={`w-2 h-2 rounded-full flex-shrink-0 ${
                  run.status === 'completed' ? 'bg-nor-green' :
                  run.status === 'failed' ? 'bg-red-500' : 'bg-yellow-400'
                }`} />
                <span className="text-neutral-400 text-xs">
                  {run.started_at ? new Date(run.started_at).toLocaleString('ar-EG') : '—'}
                </span>
                <span className="text-neutral-300">{run.processed_count ?? 0} مقال</span>
                {run.error_message && <span className="text-red-400 text-xs truncate">{run.error_message}</span>}
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Recent articles */}
      <section className="space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="font-readex font-bold text-white text-lg">آخر المقالات</h2>
          <Link href="/admin/articles" className="text-sm text-nor-green font-readex hover:underline">
            عرض الكل
          </Link>
        </div>

        <div className="space-y-2">
          {isLoading
            ? Array.from({ length: 5 }).map((_, i) => (
                <div key={i} className="h-16 bg-neutral-900 rounded-xl animate-pulse" />
              ))
            : ((data?.articles?.articles ?? []) as any[]).map((a: any) => (
                <div key={a.id} className="bg-neutral-900 border border-neutral-800 rounded-xl px-4 py-3 flex items-center gap-3">
                  {a.image_url
                    ? <img src={a.image_url} alt="" className="w-12 h-9 object-cover rounded flex-shrink-0" onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }} />
                    : <div className="w-12 h-9 bg-neutral-800 rounded flex-shrink-0" />
                  }
                  <div className="flex-1 min-w-0">
                    <p className="truncate font-amiri text-white">{a.title_ar}</p>
                    <p className="text-xs text-neutral-500 font-readex">{a.source} · {new Date(a.created_at).toLocaleDateString('ar-EG')}</p>
                  </div>
                  <Link href={`/admin/articles/${a.id}`} className="text-xs text-nor-green font-readex hover:underline flex-shrink-0">
                    تعديل
                  </Link>
                </div>
              ))
          }
        </div>

        <Link
          href="/admin/articles/new"
          className="block w-full text-center py-3 rounded-xl border border-dashed border-neutral-700 text-sm font-readex text-neutral-500 hover:border-nor-green hover:text-nor-green transition-colors"
        >
          + كتابة مقال جديد
        </Link>
      </section>
    </div>
  );
}
