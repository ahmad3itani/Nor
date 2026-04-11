import { notFound } from 'next/navigation';
import { dbGet, dbAll } from '@/lib/db';
import { formatDistanceToNow } from 'date-fns';
import { ar } from 'date-fns/locale';
import Link from 'next/link';
import type { Metadata } from 'next';
import Breadcrumbs from '@/components/ui/Breadcrumbs';

export const revalidate = 300; // ISR 5 minutes

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL || 'https://nor.com';

type Props = { params: { slug: string } };

function parseTags(raw: string | null): string[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function excerpt(body: string, maxLen = 160): string {
  const clean = body.replace(/\n+/g, ' ').trim();
  return clean.length <= maxLen ? clean : clean.slice(0, maxLen - 1) + '…';
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const article = await dbGet<any>(
    'SELECT title_ar, body_ar, image_url, source, created_at FROM articles WHERE slug = ? AND published = 1',
    [params.slug]
  );

  if (!article) return { title: 'خبر غير موجود' };

  const desc = excerpt(article.body_ar);
  const articleUrl = `${SITE_URL}/news/${params.slug}`;

  return {
    title: article.title_ar,
    description: desc,
    alternates: { canonical: articleUrl },
    openGraph: {
      title: article.title_ar,
      description: desc,
      url: articleUrl,
      siteName: 'نور - nōr',
      locale: 'ar_SA',
      type: 'article',
      publishedTime: article.created_at,
      authors: ['نور - nōr'],
      images: article.image_url
        ? [{ url: article.image_url, alt: article.title_ar }]
        : [],
    },
    twitter: {
      card: article.image_url ? 'summary_large_image' : 'summary',
      title: article.title_ar,
      description: desc,
      images: article.image_url ? [article.image_url] : [],
    },
  };
}

export default async function ArticlePage({ params }: Props) {
  const article = await dbGet<any>(
    'SELECT * FROM articles WHERE slug = ? AND published = 1',
    [params.slug]
  );

  if (!article) notFound();

  const tags = parseTags(article.tags);
  const publishedAt = new Date(article.created_at);
  const timeAgo = formatDistanceToNow(publishedAt, { addSuffix: true, locale: ar });
  const formattedDate = publishedAt.toLocaleDateString('ar-EG', { year: 'numeric', month: 'long', day: 'numeric' });
  const formattedTime = publishedAt.toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' });
  const readingTime = Math.max(1, Math.ceil(article.body_ar.split(/\s+/).filter(Boolean).length / 180));
  const articleUrl = `${SITE_URL}/news/${params.slug}`;
  const desc = excerpt(article.body_ar);

  const relatedBySource = await dbAll<any>(
    `SELECT id, slug, title_ar, source, created_at, image_url
     FROM articles WHERE slug != ? AND source = ? AND published = 1
     ORDER BY created_at DESC LIMIT 3`,
    [params.slug, article.source]
  );

  const tagConditions = tags.slice(0, 3).map(() => 'tags LIKE ?').join(' OR ');
  const relatedByTags = tags.length > 0
    ? await dbAll<any>(
        `SELECT id, slug, title_ar, source, created_at, image_url
         FROM articles WHERE slug != ? AND (${tagConditions}) AND published = 1
         ORDER BY created_at DESC LIMIT 6`,
        [params.slug, ...tags.slice(0, 3).map((t: string) => `%${t}%`)]
      )
    : [];

  const relatedArticles = [...relatedBySource, ...relatedByTags]
    .filter((c, i, all) => all.findIndex((x) => x.slug === c.slug) === i)
    .slice(0, 4);

  // JSON-LD — NewsArticle schema
  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'NewsArticle',
    headline: article.title_ar,
    description: desc,
    url: articleUrl,
    datePublished: publishedAt.toISOString(),
    dateModified: publishedAt.toISOString(),
    inLanguage: 'ar',
    ...(article.image_url ? {
      image: {
        '@type': 'ImageObject',
        url: article.image_url,
        caption: article.title_ar,
      },
    } : {}),
    author: {
      '@type': 'Organization',
      name: 'نور - nōr',
      url: SITE_URL,
    },
    publisher: {
      '@type': 'Organization',
      name: 'نور - nōr',
      url: SITE_URL,
      logo: {
        '@type': 'ImageObject',
        url: `${SITE_URL}/logo.png`,
      },
    },
    mainEntityOfPage: {
      '@type': 'WebPage',
      '@id': articleUrl,
    },
    keywords: tags.join(', '),
    articleSection: 'كرة القدم',
    copyrightHolder: { '@type': 'Organization', name: 'نور - nōr' },
  };

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />

      <div className="max-w-6xl mx-auto space-y-8">
        <Breadcrumbs items={[
          { label: 'الأخبار', href: '/news' },
          { label: article.title_ar.slice(0, 50) + (article.title_ar.length > 50 ? '…' : '') },
        ]} />

        <article className="grid gap-8 lg:grid-cols-[1.2fr_0.8fr]">
          {/* ── Main content ── */}
          <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 md:p-10 shadow-2xl">
            <div className="flex flex-wrap items-center gap-3 mb-6 font-ibm text-sm text-neutral-400">
              <span className="bg-nor-green/10 text-nor-green px-3 py-1 rounded-full font-readex font-medium">
                {article.source}
              </span>
              <span>•</span>
              <time dateTime={publishedAt.toISOString()}>{timeAgo}</time>
              <span>•</span>
              <span>{readingTime} دقائق قراءة</span>
            </div>

            <h1 className="text-2xl sm:text-3xl md:text-5xl font-bold font-amiri leading-tight mb-8 text-white">
              {article.title_ar}
            </h1>

            {article.image_url ? (
              <div className="mb-8 overflow-hidden rounded-3xl border border-neutral-800 bg-neutral-950">
                <img
                  src={article.image_url}
                  alt={article.title_ar}
                  className="h-full w-full object-cover max-h-[420px]"
                  loading="eager"
                />
              </div>
            ) : null}

            <div className="prose prose-invert prose-lg max-w-none font-ibm leading-relaxed text-neutral-300">
              {article.body_ar.split('\n').filter(Boolean).map((paragraph: string, idx: number) => (
                <p key={idx} className="mb-4">{paragraph}</p>
              ))}
            </div>

            {tags.length > 0 && (
              <div className="mt-10 pt-6 border-t border-neutral-800">
                <h3 className="text-neutral-500 text-sm font-readex mb-3">الموضوعات المرتبطة</h3>
                <div className="flex flex-wrap gap-2">
                  {tags.map((tag: string, idx: number) => (
                    <span key={idx} className="bg-neutral-800 text-neutral-300 px-3 py-1 rounded-lg text-sm font-readex">
                      #{tag}
                    </span>
                  ))}
                </div>
              </div>
            )}
          </div>

          {/* ── Sidebar ── */}
          <aside className="space-y-6">
            <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6">
              <h2 className="text-xl font-bold font-readex border-r-4 border-nor-green pr-4 mb-5">بيانات الخبر</h2>
              <div className="space-y-4 text-sm font-ibm">
                <div>
                  <p className="text-neutral-500">المصدر</p>
                  <p className="mt-1 text-white font-bold">{article.source}</p>
                </div>
                <div>
                  <p className="text-neutral-500">تاريخ النشر</p>
                  <p className="mt-1 text-white">{formattedDate}</p>
                </div>
                <div>
                  <p className="text-neutral-500">الوقت</p>
                  <p className="mt-1 text-white">{formattedTime}</p>
                </div>
                <div>
                  <p className="text-neutral-500">رابط المصدر</p>
                  <a
                    href={article.source_url}
                    target="_blank"
                    rel="noopener noreferrer nofollow"
                    className="mt-1 inline-block text-nor-green hover:underline break-all"
                  >
                    فتح المصدر الأصلي ↗
                  </a>
                </div>
              </div>
            </div>

            {/* Share */}
            <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6">
              <h2 className="text-xl font-bold font-readex border-r-4 border-nor-green pr-4 mb-4">شارك الخبر</h2>
              <div className="flex flex-wrap gap-2">
                <a
                  href={`https://twitter.com/intent/tweet?text=${encodeURIComponent(article.title_ar)}&url=${encodeURIComponent(articleUrl)}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-2 px-4 py-2 rounded-full bg-neutral-800 border border-neutral-700 text-sm font-readex text-white hover:border-nor-green transition-colors"
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-4.714-6.231-5.401 6.231H2.746l7.73-8.835L1.254 2.25H8.08l4.253 5.622zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg>
                  X / تويتر
                </a>
                <a
                  href={`https://wa.me/?text=${encodeURIComponent(article.title_ar + ' ' + articleUrl)}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-2 px-4 py-2 rounded-full bg-neutral-800 border border-neutral-700 text-sm font-readex text-white hover:border-nor-green transition-colors"
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z"/></svg>
                  واتساب
                </a>
              </div>
            </div>

            {relatedArticles.length > 0 ? (
              <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6">
                <h2 className="text-xl font-bold font-readex border-r-4 border-nor-green pr-4 mb-5">أخبار ذات صلة</h2>
                <div className="space-y-4">
                  {relatedArticles.map((related) => (
                    <Link
                      key={related.id}
                      href={`/news/${related.slug}`}
                      className="block rounded-2xl border border-neutral-800 bg-neutral-950/70 p-4 hover:border-nor-green/40 transition-colors"
                    >
                      {related.image_url ? (
                        <div className="mb-3 overflow-hidden rounded-xl border border-neutral-800">
                          <img src={related.image_url} alt={related.title_ar} className="h-36 w-full object-cover" loading="lazy" />
                        </div>
                      ) : null}
                      <p className="text-xs text-neutral-500 font-readex">{related.source}</p>
                      <p className="mt-2 font-amiri text-lg font-bold text-white leading-snug">{related.title_ar}</p>
                      <p className="mt-2 text-xs text-neutral-500 font-ibm">
                        {formatDistanceToNow(new Date(related.created_at), { addSuffix: true, locale: ar })}
                      </p>
                    </Link>
                  ))}
                </div>
              </div>
            ) : null}
          </aside>
        </article>
      </div>
    </>
  );
}
