'use client';
import { useEffect, useState } from 'react';
import Link from 'next/link';
import { formatDistanceToNow } from 'date-fns';
import { ar } from 'date-fns/locale';

interface Article {
  slug: string;
  title_ar: string;
  source: string;
  image_url: string | null;
  views: number;
  created_at: string;
}

export default function MostRead() {
  const [articles, setArticles] = useState<Article[]>([]);

  useEffect(() => {
    fetch('/api/news/most-read')
      .then((r) => r.json())
      .then((d) => setArticles(d.items || []))
      .catch(() => {});
  }, []);

  if (articles.length === 0) return null;

  return (
    <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-5">
      <h2 className="text-lg font-bold font-readex border-r-4 border-nor-green pr-3 mb-4">
        الأكثر قراءة
      </h2>
      <ol className="space-y-4">
        {articles.map((article, i) => (
          <li key={article.slug}>
            <Link
              href={`/news/${article.slug}`}
              className="flex gap-3 group"
            >
              <span className="text-2xl font-bold text-nor-green/30 font-readex leading-none w-6 shrink-0 mt-1">
                {i + 1}
              </span>
              <div className="min-w-0">
                <p className="font-amiri font-bold text-white leading-snug group-hover:text-nor-green transition-colors line-clamp-2">
                  {article.title_ar}
                </p>
                <p className="text-xs text-neutral-500 font-ibm mt-1">
                  {article.views > 0 && `${article.views.toLocaleString('ar-EG')} مشاهدة · `}
                  {formatDistanceToNow(new Date(article.created_at), { addSuffix: true, locale: ar })}
                </p>
              </div>
            </Link>
          </li>
        ))}
      </ol>
    </div>
  );
}
