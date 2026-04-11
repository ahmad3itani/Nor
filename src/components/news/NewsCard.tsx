import Link from 'next/link';
import { formatDistanceToNow } from 'date-fns';
import { ar } from 'date-fns/locale';

// Map source names to Arabic sport categories for SEO keyword richness
function getCategoryLabel(source: string, tags: string[]): string {
  const lower = source.toLowerCase();
  if (lower.includes('transfer') || tags.some(t => t.includes('انتقال'))) return 'انتقالات';
  if (lower.includes('champion')) return 'دوري الأبطال';
  if (tags.some(t => ['ريال مدريد','برشلونة','لاليغا'].includes(t))) return 'لاليغا';
  if (tags.some(t => ['مانشستر','ليفربول','آرسنال','بريميرليغ'].includes(t))) return 'البريميرليغ';
  if (tags.some(t => ['السعودي','الهلال','النصر'].includes(t))) return 'الدوري السعودي';
  return 'كرة القدم';
}

// Pitch-pattern SVG as inline data URI for article fallback images
const FALLBACK_PATTERNS = [
  'from-emerald-950 to-neutral-900',
  'from-blue-950 to-neutral-900',
  'from-purple-950 to-neutral-900',
  'from-red-950 to-neutral-900',
];

export default function NewsCard({ article, featured = false }: { article: any; featured?: boolean }) {
  const timeAgo = formatDistanceToNow(new Date(article.created_at), { addSuffix: true, locale: ar });
  const tags: string[] = article.tags ? JSON.parse(article.tags) : [];
  const category = getCategoryLabel(article.source, tags);
  const readingTime = Math.max(1, Math.ceil((article.body_ar || '').split(/\s+/).filter(Boolean).length / 180));
  const patternIdx = article.id ? article.id % FALLBACK_PATTERNS.length : 0;

  if (featured) {
    return (
      <Link href={`/news/${article.slug}`} className="block group">
        <div className="relative overflow-hidden rounded-3xl border border-neutral-800 bg-neutral-900 hover:border-nor-green/50 transition-all duration-300 hover:shadow-[0_0_40px_rgba(0,255,133,0.08)]">
          {/* Image */}
          <div className="relative h-64 sm:h-80 overflow-hidden">
            {article.image_url ? (
              <img
                src={article.image_url}
                alt={article.title_ar}
                className="w-full h-full object-cover transition-transform duration-700 group-hover:scale-105"
                loading="eager"
              />
            ) : (
              <div className={`w-full h-full bg-gradient-to-br ${FALLBACK_PATTERNS[patternIdx]} flex items-center justify-center`}>
                <svg width="120" height="80" viewBox="0 0 800 320" fill="none" opacity="0.08">
                  <rect x="40" y="20" width="720" height="280" rx="4" stroke="white" strokeWidth="2"/>
                  <line x1="400" y1="20" x2="400" y2="300" stroke="white" strokeWidth="2"/>
                  <circle cx="400" cy="160" r="60" stroke="white" strokeWidth="2"/>
                  <circle cx="400" cy="160" r="4" fill="white"/>
                </svg>
              </div>
            )}
            {/* Gradient overlay */}
            <div className="absolute inset-0 bg-gradient-to-t from-neutral-900 via-neutral-900/40 to-transparent" />
            {/* Category badge */}
            <div className="absolute top-4 right-4 flex items-center gap-2">
              <span className="px-3 py-1 bg-nor-green text-black text-xs font-bold rounded-full font-readex shadow-lg">
                {category}
              </span>
              <span className="px-2.5 py-1 bg-black/60 backdrop-blur-sm text-white text-xs rounded-full font-readex border border-white/10">
                {article.source}
              </span>
            </div>
          </div>

          {/* Content */}
          <div className="p-6">
            <h2 className="text-2xl sm:text-3xl font-bold font-amiri leading-tight mb-3 group-hover:text-nor-green transition-colors text-white">
              {article.title_ar}
            </h2>
            <p className="text-neutral-400 font-ibm line-clamp-2 text-sm leading-relaxed mb-4">
              {article.body_ar}
            </p>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3 text-xs text-neutral-500 font-ibm">
                <span className="flex items-center gap-1">
                  <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
                  {timeAgo}
                </span>
                <span>•</span>
                <span>{readingTime} دقيقة قراءة</span>
              </div>
              <span className="text-nor-green text-xs font-readex font-bold flex items-center gap-1 group-hover:gap-2 transition-all">
                اقرأ الخبر
                <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="m15 18-6-6 6-6"/></svg>
              </span>
            </div>
          </div>
        </div>
      </Link>
    );
  }

  return (
    <Link href={`/news/${article.slug}`} className="block group">
      <div className="bg-neutral-900 border border-neutral-800 rounded-2xl overflow-hidden transition-all duration-300 hover:border-nor-green/50 hover:shadow-[0_0_30px_rgba(0,255,133,0.07)] flex flex-col sm:flex-row">

        {/* Image — left column on sm+ */}
        <div className="relative sm:w-52 sm:shrink-0 h-44 sm:h-auto overflow-hidden bg-neutral-800">
          {article.image_url ? (
            <img
              src={article.image_url}
              alt={article.title_ar}
              className="w-full h-full object-cover transition-transform duration-500 group-hover:scale-105"
              loading="lazy"
            />
          ) : (
            <div className={`w-full h-full bg-gradient-to-br ${FALLBACK_PATTERNS[patternIdx]} flex items-center justify-center`}>
              <svg width="60" height="40" viewBox="0 0 800 320" fill="none" opacity="0.15">
                <rect x="40" y="20" width="720" height="280" rx="4" stroke="white" strokeWidth="3"/>
                <line x1="400" y1="20" x2="400" y2="300" stroke="white" strokeWidth="3"/>
                <circle cx="400" cy="160" r="60" stroke="white" strokeWidth="3"/>
              </svg>
            </div>
          )}
          {/* Category pill overlaid on image */}
          <span className="absolute bottom-2 right-2 px-2 py-0.5 bg-nor-green text-black text-[10px] font-bold rounded font-readex">
            {category}
          </span>
        </div>

        {/* Text */}
        <div className="flex-1 p-4 sm:p-5 flex flex-col justify-between min-w-0">
          <div>
            <div className="flex items-center gap-2 mb-2">
              <span className="px-2 py-0.5 bg-neutral-800 text-neutral-400 text-[11px] font-readex rounded">
                {article.source}
              </span>
              <span className="text-neutral-600 text-[11px] font-ibm flex items-center gap-1">
                <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
                {timeAgo}
              </span>
            </div>
            <h2 className="text-base sm:text-lg font-bold font-amiri leading-snug mb-2 group-hover:text-nor-green transition-colors line-clamp-3">
              {article.title_ar}
            </h2>
            <p className="text-neutral-500 font-ibm line-clamp-2 text-xs leading-relaxed hidden sm:block">
              {article.body_ar}
            </p>
          </div>

          <div className="flex items-center justify-between mt-3">
            <div className="flex flex-wrap gap-1.5">
              {tags.slice(0, 2).map((tag: string, idx: number) => (
                <span key={idx} className="text-[10px] text-neutral-600 bg-neutral-800/60 px-2 py-0.5 rounded font-readex">
                  #{tag}
                </span>
              ))}
            </div>
            <span className="text-[11px] text-neutral-600 font-ibm shrink-0">{readingTime} د</span>
          </div>
        </div>
      </div>
    </Link>
  );
}
