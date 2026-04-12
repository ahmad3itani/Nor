'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';

const CATEGORIES = [
  { value: 'general', label: 'أخبار عامة' },
  { value: 'transfers', label: 'انتقالات' },
  { value: 'injuries', label: 'إصابات' },
  { value: 'match-report', label: 'تقرير مباراة' },
  { value: 'analysis', label: 'تحليل' },
];

type ArticleFields = {
  title_ar: string;
  body_ar: string;
  excerpt_ar: string;
  image_url: string;
  category: string;
  tags: string;
  teams: string;
  featured: boolean;
  published: boolean;
  source: string;
  source_url: string;
  slug: string;
};

const EMPTY: ArticleFields = {
  title_ar: '',
  body_ar: '',
  excerpt_ar: '',
  image_url: '',
  category: 'general',
  tags: '',
  teams: '',
  featured: false,
  published: true,
  source: 'manual',
  source_url: '',
  slug: '',
};

function parseJsonList(val: any): string {
  if (typeof val === 'string') {
    try { return JSON.parse(val).join(', '); } catch { return val; }
  }
  if (Array.isArray(val)) return val.join(', ');
  return '';
}

type Props = {
  articleId?: number;
};

export default function ArticleEditor({ articleId }: Props) {
  const router = useRouter();
  const isEdit = !!articleId;

  const [fields, setFields] = useState<ArticleFields>(EMPTY);
  const [loading, setLoading] = useState(isEdit);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [previewBody, setPreviewBody] = useState(false);

  useEffect(() => {
    if (!isEdit) return;
    fetch(`/api/admin/articles/${articleId}`)
      .then(r => r.json())
      .then(d => {
        if (d.error) { setError(d.error); return; }
        const a = d.article;
        setFields({
          title_ar: a.title_ar || '',
          body_ar: a.body_ar || '',
          excerpt_ar: a.excerpt_ar || '',
          image_url: a.image_url || '',
          category: a.category || 'general',
          tags: parseJsonList(a.tags),
          teams: parseJsonList(a.teams),
          featured: a.featured === 1,
          published: a.published === 1,
          source: a.source || 'manual',
          source_url: a.source_url || '',
          slug: a.slug || '',
        });
      })
      .catch(e => setError(e.message))
      .finally(() => setLoading(false));
  }, [articleId, isEdit]);

  function set(key: keyof ArticleFields, value: string | boolean) {
    setFields(f => ({ ...f, [key]: value }));
    setSaved(false);
  }

  async function handleSave() {
    if (!fields.title_ar.trim() || !fields.body_ar.trim()) {
      setError('العنوان والمحتوى مطلوبان');
      return;
    }
    setSaving(true);
    setError(null);

    const tagsArr = fields.tags.split(',').map(t => t.trim()).filter(Boolean);
    const teamsArr = fields.teams.split(',').map(t => t.trim()).filter(Boolean);

    const payload = {
      title_ar: fields.title_ar.trim(),
      body_ar: fields.body_ar.trim(),
      excerpt_ar: fields.excerpt_ar.trim() || null,
      image_url: fields.image_url.trim() || null,
      category: fields.category,
      tags: tagsArr,
      teams: teamsArr,
      featured: fields.featured ? 1 : 0,
      published: fields.published ? 1 : 0,
      source: fields.source.trim() || 'manual',
      source_url: fields.source_url.trim() || '',
      ...(isEdit ? {} : { slug: fields.slug.trim() || undefined }),
    };

    try {
      const url = isEdit ? `/api/admin/articles/${articleId}` : '/api/admin/articles';
      const method = isEdit ? 'PATCH' : 'POST';
      const res = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'فشل الحفظ');

      setSaved(true);
      if (!isEdit && data.id) {
        router.push(`/admin/articles/${data.id}`);
      }
    } catch (e: any) {
      setError(e.message);
    } finally {
      setSaving(false);
    }
  }

  if (loading) return (
    <div className="space-y-4 max-w-4xl">
      {[1,2,3,4].map(i => <div key={i} className="h-12 bg-neutral-900 rounded-xl animate-pulse" />)}
    </div>
  );

  return (
    <div className="max-w-4xl space-y-6">
      {/* Top bar */}
      <div className="flex items-center gap-3 flex-wrap">
        <Link href="/admin/articles" className="text-sm text-neutral-500 hover:text-white font-readex transition-colors">
          ← المقالات
        </Link>
        <span className="text-neutral-700">/</span>
        <span className="text-sm text-neutral-300 font-readex">{isEdit ? 'تعديل مقال' : 'مقال جديد'}</span>

        <div className="mr-auto flex items-center gap-2">
          {isEdit && fields.slug && (
            <Link
              href={`/news/${fields.slug}`}
              target="_blank"
              className="px-3 py-1.5 text-xs rounded-full border border-neutral-700 text-neutral-400 hover:text-nor-green hover:border-nor-green font-readex transition-colors"
            >
              عرض المقال ↗
            </Link>
          )}
          <button
            onClick={handleSave}
            disabled={saving}
            className="px-5 py-2 rounded-full bg-nor-green text-black text-sm font-readex font-bold disabled:opacity-60 hover:bg-nor-green/90 transition-colors"
          >
            {saving ? 'جاري الحفظ...' : saved ? '✓ محفوظ' : 'حفظ'}
          </button>
        </div>
      </div>

      {error && (
        <div className="bg-red-950 border border-red-800 rounded-xl px-4 py-3 text-sm text-red-300 font-readex">
          {error}
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Left — main content */}
        <div className="lg:col-span-2 space-y-5">
          {/* Title */}
          <div>
            <label className="block text-xs text-neutral-500 font-readex mb-1.5">العنوان *</label>
            <input
              type="text"
              value={fields.title_ar}
              onChange={e => set('title_ar', e.target.value)}
              placeholder="عنوان المقال..."
              dir="rtl"
              className="w-full bg-neutral-900 border border-neutral-800 rounded-xl px-4 py-3 text-white font-amiri text-xl focus:border-nor-green outline-none placeholder:text-neutral-600 transition-colors"
            />
          </div>

          {/* Excerpt */}
          <div>
            <label className="block text-xs text-neutral-500 font-readex mb-1.5">المقتطف</label>
            <textarea
              value={fields.excerpt_ar}
              onChange={e => set('excerpt_ar', e.target.value)}
              placeholder="ملخص جذاب للمقال (100-160 حرف)..."
              dir="rtl"
              rows={2}
              className="w-full bg-neutral-900 border border-neutral-800 rounded-xl px-4 py-3 text-white font-ibm resize-none focus:border-nor-green outline-none placeholder:text-neutral-600 transition-colors text-sm"
            />
            <p className="text-xs text-neutral-600 mt-1 font-readex">{fields.excerpt_ar.length} / 160</p>
          </div>

          {/* Body */}
          <div>
            <div className="flex items-center justify-between mb-1.5">
              <label className="text-xs text-neutral-500 font-readex">المحتوى *</label>
              <button
                onClick={() => setPreviewBody(v => !v)}
                className="text-xs text-neutral-500 hover:text-nor-green font-readex transition-colors"
              >
                {previewBody ? 'تحرير' : 'معاينة'}
              </button>
            </div>
            {previewBody ? (
              <div
                className="w-full bg-neutral-900 border border-neutral-800 rounded-xl px-4 py-3 min-h-64 text-white font-amiri text-base leading-relaxed prose prose-invert max-w-none"
                dir="rtl"
                dangerouslySetInnerHTML={{ __html: fields.body_ar }}
              />
            ) : (
              <textarea
                value={fields.body_ar}
                onChange={e => set('body_ar', e.target.value)}
                placeholder="اكتب محتوى المقال هنا..."
                dir="rtl"
                rows={18}
                className="w-full bg-neutral-900 border border-neutral-800 rounded-xl px-4 py-3 text-white font-amiri text-base leading-relaxed resize-y focus:border-nor-green outline-none placeholder:text-neutral-600 transition-colors"
              />
            )}
            <p className="text-xs text-neutral-600 mt-1 font-readex">{fields.body_ar.length.toLocaleString()} حرف</p>
          </div>
        </div>

        {/* Right — metadata */}
        <div className="space-y-5">
          {/* Publish status */}
          <div className="bg-neutral-900 border border-neutral-800 rounded-xl p-4 space-y-3">
            <h3 className="text-xs text-neutral-500 font-readex font-bold uppercase tracking-wider">النشر</h3>
            <label className="flex items-center justify-between cursor-pointer">
              <span className="text-sm text-white font-readex">منشور</span>
              <button
                onClick={() => set('published', !fields.published)}
                className={`relative w-10 h-5 rounded-full transition-colors ${fields.published ? 'bg-nor-green' : 'bg-neutral-700'}`}
              >
                <span className={`absolute top-0.5 w-4 h-4 bg-white rounded-full shadow transition-transform ${fields.published ? 'translate-x-5' : 'translate-x-0.5'}`} />
              </button>
            </label>
            <label className="flex items-center justify-between cursor-pointer">
              <span className="text-sm text-white font-readex">مميز (Featured)</span>
              <button
                onClick={() => set('featured', !fields.featured)}
                className={`relative w-10 h-5 rounded-full transition-colors ${fields.featured ? 'bg-yellow-400' : 'bg-neutral-700'}`}
              >
                <span className={`absolute top-0.5 w-4 h-4 bg-white rounded-full shadow transition-transform ${fields.featured ? 'translate-x-5' : 'translate-x-0.5'}`} />
              </button>
            </label>
          </div>

          {/* Category */}
          <div className="bg-neutral-900 border border-neutral-800 rounded-xl p-4 space-y-3">
            <h3 className="text-xs text-neutral-500 font-readex font-bold uppercase tracking-wider">التصنيف</h3>
            <div className="space-y-1.5">
              {CATEGORIES.map(c => (
                <label key={c.value} className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="radio"
                    name="category"
                    value={c.value}
                    checked={fields.category === c.value}
                    onChange={() => set('category', c.value)}
                    className="accent-nor-green"
                  />
                  <span className="text-sm text-neutral-300 font-readex">{c.label}</span>
                </label>
              ))}
            </div>
          </div>

          {/* Image */}
          <div className="bg-neutral-900 border border-neutral-800 rounded-xl p-4 space-y-3">
            <h3 className="text-xs text-neutral-500 font-readex font-bold uppercase tracking-wider">الصورة</h3>
            <input
              type="url"
              value={fields.image_url}
              onChange={e => set('image_url', e.target.value)}
              placeholder="https://..."
              dir="ltr"
              className="w-full bg-neutral-800 border border-neutral-700 rounded-lg px-3 py-2 text-white text-xs font-ibm focus:border-nor-green outline-none placeholder:text-neutral-600"
            />
            {fields.image_url && (
              <img
                src={fields.image_url}
                alt=""
                className="w-full h-28 object-cover rounded-lg"
                onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }}
              />
            )}
          </div>

          {/* Tags & Teams */}
          <div className="bg-neutral-900 border border-neutral-800 rounded-xl p-4 space-y-3">
            <h3 className="text-xs text-neutral-500 font-readex font-bold uppercase tracking-wider">الوسوم والأندية</h3>
            <div>
              <label className="text-xs text-neutral-500 font-readex mb-1 block">وسوم (مفصولة بفاصلة)</label>
              <input
                type="text"
                value={fields.tags}
                onChange={e => set('tags', e.target.value)}
                placeholder="كرة القدم، دوري أبطال..."
                dir="rtl"
                className="w-full bg-neutral-800 border border-neutral-700 rounded-lg px-3 py-2 text-white text-sm font-ibm focus:border-nor-green outline-none placeholder:text-neutral-600"
              />
            </div>
            <div>
              <label className="text-xs text-neutral-500 font-readex mb-1 block">الأندية (مفصولة بفاصلة)</label>
              <input
                type="text"
                value={fields.teams}
                onChange={e => set('teams', e.target.value)}
                placeholder="ريال مدريد، برشلونة..."
                dir="rtl"
                className="w-full bg-neutral-800 border border-neutral-700 rounded-lg px-3 py-2 text-white text-sm font-ibm focus:border-nor-green outline-none placeholder:text-neutral-600"
              />
            </div>
          </div>

          {/* Source */}
          <div className="bg-neutral-900 border border-neutral-800 rounded-xl p-4 space-y-3">
            <h3 className="text-xs text-neutral-500 font-readex font-bold uppercase tracking-wider">المصدر</h3>
            <input
              type="text"
              value={fields.source}
              onChange={e => set('source', e.target.value)}
              placeholder="manual"
              dir="ltr"
              className="w-full bg-neutral-800 border border-neutral-700 rounded-lg px-3 py-2 text-white text-sm font-ibm focus:border-nor-green outline-none"
            />
            <input
              type="url"
              value={fields.source_url}
              onChange={e => set('source_url', e.target.value)}
              placeholder="https://..."
              dir="ltr"
              className="w-full bg-neutral-800 border border-neutral-700 rounded-lg px-3 py-2 text-white text-sm font-ibm focus:border-nor-green outline-none placeholder:text-neutral-600"
            />
          </div>

          {/* Slug (create only) */}
          {!isEdit && (
            <div className="bg-neutral-900 border border-neutral-800 rounded-xl p-4 space-y-2">
              <h3 className="text-xs text-neutral-500 font-readex font-bold uppercase tracking-wider">الرابط (اختياري)</h3>
              <input
                type="text"
                value={fields.slug}
                onChange={e => set('slug', e.target.value)}
                placeholder="سيُولَّد تلقائياً"
                dir="ltr"
                className="w-full bg-neutral-800 border border-neutral-700 rounded-lg px-3 py-2 text-white text-sm font-ibm focus:border-nor-green outline-none placeholder:text-neutral-600"
              />
            </div>
          )}
        </div>
      </div>

      {/* Bottom save */}
      <div className="flex justify-end pt-4 border-t border-neutral-800">
        <button
          onClick={handleSave}
          disabled={saving}
          className="px-8 py-2.5 rounded-full bg-nor-green text-black text-sm font-readex font-bold disabled:opacity-60 hover:bg-nor-green/90 transition-colors"
        >
          {saving ? 'جاري الحفظ...' : saved ? '✓ محفوظ' : 'حفظ المقال'}
        </button>
      </div>
    </div>
  );
}
