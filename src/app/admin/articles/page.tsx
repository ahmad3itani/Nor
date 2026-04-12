'use client';

import { useState, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import Link from 'next/link';

const CATEGORY_LABELS: Record<string, string> = {
  transfers: 'انتقالات',
  injuries: 'إصابات',
  'match-report': 'تقرير مباراة',
  analysis: 'تحليل',
  general: 'أخبار',
};

type Article = {
  id: number;
  slug: string;
  title_ar: string;
  excerpt_ar: string | null;
  category: string;
  featured: number;
  published: number;
  image_url: string | null;
  source: string;
  views: number;
  created_at: string;
};

type EditFields = {
  title_ar: string;
  excerpt_ar: string;
  category: string;
  image_url: string;
  featured: number;
  published: number;
};

function EditModal({ article, onClose, onSave }: {
  article: Article;
  onClose: () => void;
  onSave: (id: number, fields: EditFields) => void;
}) {
  const [fields, setFields] = useState<EditFields>({
    title_ar: article.title_ar,
    excerpt_ar: article.excerpt_ar || '',
    category: article.category || 'general',
    image_url: article.image_url || '',
    featured: article.featured,
    published: article.published,
  });

  function set(key: keyof EditFields, value: string | number) {
    setFields(prev => ({ ...prev, [key]: value }));
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" onClick={onClose}>
      <div
        className="bg-neutral-900 border border-neutral-700 rounded-2xl w-full max-w-2xl max-h-[90vh] overflow-y-auto"
        onClick={e => e.stopPropagation()}
      >
        <div className="p-6 border-b border-neutral-800 flex items-center justify-between">
          <h2 className="font-readex font-bold text-white text-lg">تعديل المقال</h2>
          <button onClick={onClose} className="text-neutral-400 hover:text-white text-2xl leading-none">&times;</button>
        </div>

        <div className="p-6 space-y-5">
          <div>
            <label className="block text-sm text-neutral-400 font-readex mb-1">العنوان</label>
            <input
              type="text"
              value={fields.title_ar}
              onChange={e => set('title_ar', e.target.value)}
              className="w-full bg-neutral-800 border border-neutral-700 rounded-lg px-3 py-2 text-white font-amiri text-lg focus:border-nor-green outline-none"
              dir="rtl"
            />
          </div>

          <div>
            <label className="block text-sm text-neutral-400 font-readex mb-1">المقتطف</label>
            <textarea
              value={fields.excerpt_ar}
              onChange={e => set('excerpt_ar', e.target.value)}
              rows={3}
              className="w-full bg-neutral-800 border border-neutral-700 rounded-lg px-3 py-2 text-white font-ibm resize-none focus:border-nor-green outline-none"
              dir="rtl"
            />
          </div>

          <div>
            <label className="block text-sm text-neutral-400 font-readex mb-1">رابط الصورة</label>
            <input
              type="url"
              value={fields.image_url}
              onChange={e => set('image_url', e.target.value)}
              placeholder="https://..."
              className="w-full bg-neutral-800 border border-neutral-700 rounded-lg px-3 py-2 text-white font-ibm focus:border-nor-green outline-none"
              dir="ltr"
            />
            {fields.image_url && (
              <img src={fields.image_url} alt="" className="mt-2 h-24 w-auto rounded object-cover" />
            )}
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm text-neutral-400 font-readex mb-1">التصنيف</label>
              <select
                value={fields.category}
                onChange={e => set('category', e.target.value)}
                className="w-full bg-neutral-800 border border-neutral-700 rounded-lg px-3 py-2 text-white font-readex focus:border-nor-green outline-none"
              >
                {Object.entries(CATEGORY_LABELS).map(([val, label]) => (
                  <option key={val} value={val}>{label}</option>
                ))}
              </select>
            </div>

            <div className="space-y-3 pt-6">
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={fields.featured === 1}
                  onChange={e => set('featured', e.target.checked ? 1 : 0)}
                  className="w-4 h-4 accent-nor-green"
                />
                <span className="text-sm text-white font-readex">مميز</span>
              </label>
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={fields.published === 1}
                  onChange={e => set('published', e.target.checked ? 1 : 0)}
                  className="w-4 h-4 accent-nor-green"
                />
                <span className="text-sm text-white font-readex">منشور</span>
              </label>
            </div>
          </div>
        </div>

        <div className="p-6 border-t border-neutral-800 flex justify-end gap-3">
          <button
            onClick={onClose}
            className="px-4 py-2 rounded-full border border-neutral-700 text-sm font-readex text-neutral-300 hover:border-neutral-500 transition-colors"
          >
            إلغاء
          </button>
          <button
            onClick={() => onSave(article.id, fields)}
            className="px-6 py-2 rounded-full bg-nor-green text-black text-sm font-readex font-bold hover:bg-nor-green/90 transition-colors"
          >
            حفظ
          </button>
        </div>
      </div>
    </div>
  );
}

export default function AdminArticlesPage() {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(0);
  const [editingArticle, setEditingArticle] = useState<Article | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState<number | null>(null);
  const limit = 20;

  const { data, isLoading, isError } = useQuery({
    queryKey: ['admin-articles', search, page],
    queryFn: async () => {
      const params = new URLSearchParams({
        limit: String(limit),
        offset: String(page * limit),
        ...(search ? { q: search } : {}),
      });
      const res = await fetch(`/api/admin/articles?${params}`);
      if (!res.ok) throw new Error('Failed');
      return res.json() as Promise<{ total: number; articles: Article[] }>;
    },
    staleTime: 10000,
  });

  const deleteMutation = useMutation({
    mutationFn: async (id: number) => {
      const res = await fetch(`/api/admin/articles/${id}`, { method: 'DELETE' });
      if (!res.ok) throw new Error('Delete failed');
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-articles'] });
      setDeleteConfirm(null);
    },
  });

  const editMutation = useMutation({
    mutationFn: async ({ id, fields }: { id: number; fields: EditFields }) => {
      const res = await fetch(`/api/admin/articles/${id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(fields),
      });
      if (!res.ok) throw new Error('Update failed');
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-articles'] });
      setEditingArticle(null);
    },
  });

  const handleSave = useCallback((id: number, fields: EditFields) => {
    editMutation.mutate({ id, fields });
  }, [editMutation]);

  const totalPages = data ? Math.ceil(data.total / limit) : 0;

  return (
    <div className="space-y-6 pb-16">
      {/* Header */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-3xl font-bold font-readex text-white">إدارة المقالات</h1>
          {data && (
            <p className="mt-1 text-sm text-neutral-500 font-readex">
              {data.total} مقال
            </p>
          )}
        </div>

        <input
          type="search"
          value={search}
          onChange={e => { setSearch(e.target.value); setPage(0); }}
          placeholder="بحث..."
          dir="rtl"
          className="w-full sm:w-64 bg-neutral-900 border border-neutral-700 rounded-full px-4 py-2 text-white text-sm font-readex focus:border-nor-green outline-none"
        />
      </div>

      {/* Table */}
      {isLoading ? (
        <div className="space-y-2">
          {Array.from({ length: 8 }).map((_, i) => (
            <div key={i} className="h-16 bg-neutral-900 rounded-xl animate-pulse" />
          ))}
        </div>
      ) : isError ? (
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-12 text-center">
          <p className="text-neutral-400 font-readex">تعذر تحميل المقالات</p>
        </div>
      ) : !data?.articles.length ? (
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-12 text-center">
          <p className="text-neutral-400 font-readex">لا توجد مقالات</p>
        </div>
      ) : (
        <div className="space-y-2">
          {data.articles.map(article => (
            <div
              key={article.id}
              className="bg-neutral-900 border border-neutral-800 rounded-xl px-4 py-3 flex items-center gap-3"
            >
              {/* Image thumbnail */}
              {article.image_url ? (
                <img
                  src={article.image_url}
                  alt=""
                  className="w-14 h-10 object-cover rounded-lg flex-shrink-0"
                  onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }}
                />
              ) : (
                <div className="w-14 h-10 bg-neutral-800 rounded-lg flex-shrink-0 flex items-center justify-center">
                  <span className="text-neutral-600 text-xs">لا صورة</span>
                </div>
              )}

              {/* Main info */}
              <div className="flex-1 min-w-0">
                <p className="truncate font-amiri text-white leading-tight" dir="rtl">
                  {article.title_ar}
                </p>
                <div className="flex items-center gap-2 mt-0.5 flex-wrap">
                  <span className="text-xs text-neutral-500 font-readex">
                    {new Date(article.created_at).toLocaleDateString('ar-EG')}
                  </span>
                  <span className="text-xs text-neutral-600">·</span>
                  <span className="text-xs text-neutral-500 font-readex">{article.source}</span>
                  {article.category && (
                    <>
                      <span className="text-xs text-neutral-600">·</span>
                      <span className="text-xs text-nor-green/80 font-readex">
                        {CATEGORY_LABELS[article.category] || article.category}
                      </span>
                    </>
                  )}
                  {article.featured === 1 && (
                    <span className="text-xs bg-yellow-500/10 text-yellow-400 px-1.5 py-0.5 rounded font-readex">مميز</span>
                  )}
                  {article.published === 0 && (
                    <span className="text-xs bg-red-500/10 text-red-400 px-1.5 py-0.5 rounded font-readex">مخفي</span>
                  )}
                </div>
              </div>

              {/* Views */}
              <span className="text-xs text-neutral-600 font-readex flex-shrink-0 hidden sm:block">
                {article.views} مشاهدة
              </span>

              {/* Actions */}
              <div className="flex items-center gap-1 flex-shrink-0">
                <Link
                  href={`/news/${article.slug}`}
                  target="_blank"
                  className="p-1.5 text-neutral-500 hover:text-nor-green transition-colors rounded-lg hover:bg-nor-green/10"
                  title="عرض"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                    <path strokeLinecap="round" strokeLinejoin="round" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
                  </svg>
                </Link>
                <button
                  onClick={() => setEditingArticle(article)}
                  className="p-1.5 text-neutral-500 hover:text-blue-400 transition-colors rounded-lg hover:bg-blue-400/10"
                  title="تعديل"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                    <path strokeLinecap="round" strokeLinejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                  </svg>
                </button>
                {deleteConfirm === article.id ? (
                  <div className="flex items-center gap-1">
                    <button
                      onClick={() => deleteMutation.mutate(article.id)}
                      disabled={deleteMutation.isPending}
                      className="px-2 py-1 text-xs bg-red-600 text-white rounded font-readex hover:bg-red-700 transition-colors"
                    >
                      {deleteMutation.isPending ? '...' : 'تأكيد'}
                    </button>
                    <button
                      onClick={() => setDeleteConfirm(null)}
                      className="px-2 py-1 text-xs bg-neutral-700 text-white rounded font-readex hover:bg-neutral-600 transition-colors"
                    >
                      إلغاء
                    </button>
                  </div>
                ) : (
                  <button
                    onClick={() => setDeleteConfirm(article.id)}
                    className="p-1.5 text-neutral-500 hover:text-red-400 transition-colors rounded-lg hover:bg-red-400/10"
                    title="حذف"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                    </svg>
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex items-center justify-center gap-2">
          <button
            disabled={page === 0}
            onClick={() => setPage(p => p - 1)}
            className="px-3 py-1.5 rounded-lg border border-neutral-700 text-sm font-readex text-neutral-300 disabled:opacity-40 hover:border-nor-green transition-colors"
          >
            ←
          </button>
          <span className="text-sm font-readex text-neutral-400">
            {page + 1} / {totalPages}
          </span>
          <button
            disabled={page >= totalPages - 1}
            onClick={() => setPage(p => p + 1)}
            className="px-3 py-1.5 rounded-lg border border-neutral-700 text-sm font-readex text-neutral-300 disabled:opacity-40 hover:border-nor-green transition-colors"
          >
            →
          </button>
        </div>
      )}

      {/* Edit Modal */}
      {editingArticle && (
        <EditModal
          article={editingArticle}
          onClose={() => setEditingArticle(null)}
          onSave={handleSave}
        />
      )}

      {editMutation.isError && (
        <div className="fixed bottom-4 left-4 bg-red-600 text-white px-4 py-2 rounded-lg font-readex text-sm">
          فشل الحفظ
        </div>
      )}
    </div>
  );
}
