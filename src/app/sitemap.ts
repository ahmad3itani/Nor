import type { MetadataRoute } from 'next';
import { dbAll } from '@/lib/db';

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL || 'https://nor.com';

const staticRoutes: MetadataRoute.Sitemap = [
  { url: `${SITE_URL}/`,                lastModified: new Date(), changeFrequency: 'hourly',  priority: 1.0 },
  { url: `${SITE_URL}/news`,            lastModified: new Date(), changeFrequency: 'hourly',  priority: 0.9 },
  { url: `${SITE_URL}/live`,            lastModified: new Date(), changeFrequency: 'always',  priority: 0.9 },
  { url: `${SITE_URL}/matches`,         lastModified: new Date(), changeFrequency: 'hourly',  priority: 0.8 },
  { url: `${SITE_URL}/analytics`,       lastModified: new Date(), changeFrequency: 'daily',   priority: 0.8 },
  { url: `${SITE_URL}/transfers`,       lastModified: new Date(), changeFrequency: 'daily',   priority: 0.7 },
  { url: `${SITE_URL}/injuries`,        lastModified: new Date(), changeFrequency: 'daily',   priority: 0.7 },
  { url: `${SITE_URL}/odds`,            lastModified: new Date(), changeFrequency: 'hourly',  priority: 0.7 },
  { url: `${SITE_URL}/h2h`,            lastModified: new Date(), changeFrequency: 'weekly',  priority: 0.6 },
  { url: `${SITE_URL}/compare/players`, lastModified: new Date(), changeFrequency: 'weekly',  priority: 0.6 },
  { url: `${SITE_URL}/compare/teams`,   lastModified: new Date(), changeFrequency: 'weekly',  priority: 0.6 },
  { url: `${SITE_URL}/favorites`,       lastModified: new Date(), changeFrequency: 'weekly',  priority: 0.5 },
  { url: `${SITE_URL}/watchlist`,       lastModified: new Date(), changeFrequency: 'weekly',  priority: 0.5 },
  { url: `${SITE_URL}/reminders`,       lastModified: new Date(), changeFrequency: 'weekly',  priority: 0.5 },
];

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  let articleRoutes: MetadataRoute.Sitemap = [];

  try {
    const articles = await dbAll<{ slug: string; created_at: string }>(
      `SELECT slug, created_at FROM articles WHERE published = 1 ORDER BY created_at DESC LIMIT 5000`
    );

    articleRoutes = articles.map((article) => ({
      url: `${SITE_URL}/news/${article.slug}`,
      lastModified: new Date(article.created_at),
      changeFrequency: 'monthly' as const,
      priority: 0.7,
    }));
  } catch {
    // DB not ready during build — skip article routes
  }

  return [...staticRoutes, ...articleRoutes];
}
