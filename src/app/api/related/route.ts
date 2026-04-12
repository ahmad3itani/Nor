import { NextResponse } from 'next/server';
import { dbAll } from '@/lib/db';

export const revalidate = 0;

/**
 * GET /api/related?keyword=barcelona&limit=5&slug=current-article-slug
 *
 * Returns related articles for a given keyword (matches title, body, tags, or teams).
 * Used by n8n to inject internal links before publishing.
 *
 * Response format expected by n8n Inject Links node:
 * { "links": [{ "title": "...", "url": "/news/slug" }] }
 */
export async function GET(req: Request) {
  const { searchParams } = new URL(req.url);
  const keyword = searchParams.get('keyword')?.trim() || '';
  const excludeSlug = searchParams.get('slug')?.trim() || '';
  const limit = Math.min(parseInt(searchParams.get('limit') || '5', 10), 10);

  if (!keyword) {
    return NextResponse.json({ links: [] });
  }

  const like = `%${keyword}%`;

  try {
    const articles = await dbAll<{
      slug: string;
      title_ar: string;
      created_at: string;
    }>(
      `SELECT slug, title_ar, created_at
       FROM articles
       WHERE published = 1
         AND (title_ar LIKE ? OR tags LIKE ? OR teams LIKE ?)
         ${excludeSlug ? 'AND slug != ?' : ''}
       ORDER BY created_at DESC
       LIMIT ?`,
      excludeSlug
        ? [like, like, like, excludeSlug, limit]
        : [like, like, like, limit]
    );

    const links = articles.map((a) => ({
      title: a.title_ar,
      url: `/news/${a.slug}`,
    }));

    return NextResponse.json({ links });
  } catch (err: any) {
    return NextResponse.json({ error: err.message, links: [] }, { status: 500 });
  }
}
