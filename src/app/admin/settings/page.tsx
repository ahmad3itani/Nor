'use client';

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';

type Settings = {
  paused: boolean;
  maxPerRun: number;
  maxPerDay: number;
  feedOverrides: Record<string, boolean>;
  feeds: { source: string; url: string }[];
  todayCount: number;
};

function Toggle({ on, onChange, color = 'nor-green' }: { on: boolean; onChange: (v: boolean) => void; color?: string }) {
  return (
    <button
      onClick={() => onChange(!on)}
      className={`relative w-11 h-6 rounded-full transition-colors flex-shrink-0 ${on ? (color === 'red' ? 'bg-red-500' : 'bg-nor-green') : 'bg-neutral-700'}`}
    >
      <span className={`absolute top-0.5 left-0.5 w-5 h-5 bg-white rounded-full shadow transition-transform ${on ? 'translate-x-5' : ''}`} />
    </button>
  );
}

export default function SettingsPage() {
  const queryClient = useQueryClient();
  const [saved, setSaved] = useState(false);

  const { data, isLoading } = useQuery<Settings>({
    queryKey: ['admin-settings'],
    queryFn: () => fetch('/api/admin/settings').then(r => r.json()),
    staleTime: 10000,
  });

  const [local, setLocal] = useState<Partial<Settings>>({});

  const settings: Settings | null = data ? { ...data, ...local } : null;

  function set(patch: Partial<Settings>) {
    setLocal(prev => ({ ...prev, ...patch }));
    setSaved(false);
  }

  const mutation = useMutation({
    mutationFn: async (patch: Record<string, any>) => {
      const res = await fetch('/api/admin/settings', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(patch),
      });
      if (!res.ok) throw new Error((await res.json()).error);
    },
    onSuccess: () => {
      setSaved(true);
      setLocal({});
      queryClient.invalidateQueries({ queryKey: ['admin-settings'] });
    },
  });

  function handleSave() {
    if (!settings) return;
    mutation.mutate({
      paused: settings.paused,
      maxPerRun: settings.maxPerRun,
      maxPerDay: settings.maxPerDay,
      feedOverrides: settings.feedOverrides,
    });
  }

  if (isLoading || !settings) return (
    <div className="space-y-4 max-w-2xl">
      {[1,2,3].map(i => <div key={i} className="h-24 bg-neutral-900 rounded-2xl animate-pulse" />)}
    </div>
  );

  const pctUsed = Math.min(100, Math.round((settings.todayCount / settings.maxPerDay) * 100));

  return (
    <div className="max-w-2xl space-y-6">
      {/* Save bar */}
      <div className="flex items-center justify-between">
        <p className="text-sm text-neutral-500 font-readex">إعدادات خط النشر التلقائي</p>
        <button
          onClick={handleSave}
          disabled={mutation.isPending}
          className="px-5 py-2 rounded-full bg-nor-green text-black text-sm font-readex font-bold disabled:opacity-60 hover:bg-nor-green/90 transition-colors"
        >
          {mutation.isPending ? 'جاري...' : saved ? '✓ محفوظ' : 'حفظ التغييرات'}
        </button>
      </div>

      {mutation.isError && (
        <div className="bg-red-950 border border-red-800 rounded-xl px-4 py-3 text-sm text-red-300 font-readex">
          {(mutation.error as Error).message}
        </div>
      )}

      {/* Pipeline status */}
      <section className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6 space-y-5">
        <h2 className="font-readex font-bold text-white">حالة الخط التلقائي</h2>

        <div className="flex items-center justify-between">
          <div>
            <p className="font-readex text-white text-sm">تشغيل الخط التلقائي</p>
            <p className="text-xs text-neutral-500 font-readex mt-0.5">
              {settings.paused ? 'متوقف — لن يعمل أي نشر تلقائي' : 'يعمل كل 10 دقائق عبر Vercel Cron'}
            </p>
          </div>
          <Toggle
            on={!settings.paused}
            onChange={v => set({ paused: !v })}
          />
        </div>

        {settings.paused && (
          <div className="bg-yellow-950/40 border border-yellow-800/40 rounded-xl px-4 py-3">
            <p className="text-yellow-400 text-sm font-readex">⏸ الخط متوقف. لن تُنشر أي مقالات جديدة تلقائياً حتى تستأنفه.</p>
          </div>
        )}

        {/* Today progress */}
        <div className="space-y-2">
          <div className="flex items-center justify-between text-sm font-readex">
            <span className="text-neutral-400">اليوم: {settings.todayCount} / {settings.maxPerDay} مقال</span>
            <span className={`font-bold ${pctUsed >= 90 ? 'text-red-400' : pctUsed >= 70 ? 'text-yellow-400' : 'text-nor-green'}`}>
              {pctUsed}%
            </span>
          </div>
          <div className="w-full h-2 bg-neutral-800 rounded-full overflow-hidden">
            <div
              className={`h-full rounded-full transition-all ${pctUsed >= 90 ? 'bg-red-500' : pctUsed >= 70 ? 'bg-yellow-400' : 'bg-nor-green'}`}
              style={{ width: `${pctUsed}%` }}
            />
          </div>
        </div>
      </section>

      {/* Limits */}
      <section className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6 space-y-6">
        <h2 className="font-readex font-bold text-white">حدود النشر</h2>

        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <label className="text-sm font-readex text-white">مقالات لكل تشغيل</label>
            <span className="text-nor-green font-readex font-bold text-lg">{settings.maxPerRun}</span>
          </div>
          <input
            type="range"
            min={1}
            max={20}
            value={settings.maxPerRun}
            onChange={e => set({ maxPerRun: parseInt(e.target.value) })}
            className="w-full accent-nor-green"
          />
          <div className="flex justify-between text-xs text-neutral-600 font-readex">
            <span>1</span><span>5</span><span>10</span><span>15</span><span>20</span>
          </div>
          <p className="text-xs text-neutral-500 font-readex">كم مقال يُعاد صياغته وينشر في كل دورة (كل 10 دقائق)</p>
        </div>

        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <label className="text-sm font-readex text-white">الحد اليومي</label>
            <span className="text-nor-green font-readex font-bold text-lg">{settings.maxPerDay}</span>
          </div>
          <input
            type="range"
            min={5}
            max={200}
            step={5}
            value={settings.maxPerDay}
            onChange={e => set({ maxPerDay: parseInt(e.target.value) })}
            className="w-full accent-nor-green"
          />
          <div className="flex justify-between text-xs text-neutral-600 font-readex">
            <span>5</span><span>50</span><span>100</span><span>150</span><span>200</span>
          </div>
          <p className="text-xs text-neutral-500 font-readex">أقصى عدد مقالات تُنشر يومياً عبر الخط التلقائي</p>
        </div>
      </section>

      {/* RSS Feeds */}
      <section className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6 space-y-4">
        <h2 className="font-readex font-bold text-white">مصادر RSS</h2>
        <p className="text-xs text-neutral-500 font-readex">تفعيل أو تعطيل كل مصدر بشكل مستقل</p>

        <div className="space-y-3">
          {settings.feeds.map(feed => {
            const enabled = settings.feedOverrides[feed.source] !== false;
            return (
              <div key={feed.source} className="flex items-center justify-between gap-4 py-2 border-b border-neutral-800 last:border-0">
                <div className="min-w-0">
                  <p className={`font-readex text-sm font-medium ${enabled ? 'text-white' : 'text-neutral-500'}`}>
                    {feed.source}
                  </p>
                  <p className="text-xs text-neutral-600 font-ibm truncate">{feed.url}</p>
                </div>
                <Toggle
                  on={enabled}
                  onChange={v => {
                    const overrides = { ...(settings.feedOverrides || {}) };
                    if (v) {
                      delete overrides[feed.source]; // true is the default, no need to store
                    } else {
                      overrides[feed.source] = false;
                    }
                    set({ feedOverrides: overrides });
                  }}
                />
              </div>
            );
          })}
        </div>
      </section>

      {/* Info */}
      <section className="bg-neutral-900/50 border border-neutral-800 rounded-2xl p-5 space-y-2">
        <h3 className="font-readex font-bold text-neutral-400 text-sm">معلومات النظام</h3>
        <div className="grid grid-cols-2 gap-2 text-xs font-readex">
          <div className="text-neutral-500">تكرار التشغيل</div><div className="text-neutral-300">كل 10 دقائق (Vercel Cron)</div>
          <div className="text-neutral-500">نموذج الذكاء الاصطناعي</div><div className="text-neutral-300">claude-3.5-sonnet</div>
          <div className="text-neutral-500">مزود الذكاء الاصطناعي</div><div className="text-neutral-300">OpenRouter</div>
          <div className="text-neutral-500">قاعدة البيانات</div><div className="text-neutral-300">Turso (libSQL)</div>
        </div>
      </section>
    </div>
  );
}
