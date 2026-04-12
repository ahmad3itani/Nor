import { NextRequest, NextResponse } from 'next/server';
import { dbAll, dbGet } from '@/lib/db';

function authenticate(req: NextRequest): boolean {
  const secret = process.env.N8N_WEBHOOK_SECRET;
  if (!secret) return false;
  const auth = req.headers.get('authorization') || '';
  if (auth.startsWith('Bearer ')) return auth.slice(7) === secret;
  return new URL(req.url).searchParams.get('secret') === secret;
}

/**
 * GET /api/n8n/articles?limit=10&category=transfers&slug=some-slug
 *
 * - Omit slug → returns latest articles list
 * - Pass slug → returns single article by slug
 *
 * Protected by N8N_WEBHOOK_SECRET.
 */
export async function GET(req: NextRequest) {
  if (!authenticate(req)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const { searchParams } = new URL(req.url);
  const slug = searchParams.get('slug')?.trim();
  const category = searchParams.get('category')?.trim();
  const limit = Math.min(parseInt(searchParams.get('limit') || '20', 10), 100);

  try {
    if (slug) {
      const article = await dbGet<any>(
        'SELECT * FROM articles WHERE slug = ?',
        [slug]
      );
      if (!article) return NextResponse.json({ error: 'Not found' }, { status: 404 });
      return NextResponse.json({ article });
    }

    const conditions = ['published = 1'];
    const args: any[] = [];
    if (category) { conditions.push('category = ?'); args.push(category); }

    const articles = await dbAll<any>(
      `SELECT id, slug, title_ar, excerpt_ar, category, teams, tags, image_url, views, created_at
       FROM articles WHERE ${conditions.join(' AND ')}
       ORDER BY created_at DESC LIMIT ?`,
      [...args, limit]
    );

    return NextResponse.json({ articles, count: articles.length });
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}

/**
 * PATCH /api/n8n/articles
 * Update article fields (e.g. body after re-processing, featured flag).
 * Body: { slug, ...fieldsToUpdate }
 */
export async function PATCH(req: NextRequest) {
  if (!authenticate(req)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  let body: Record<string, any>;
  try { body = await req.json(); } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 });
  }

  const { slug, ...fields } = body;
  if (!slug) return NextResponse.json({ error: 'slug required' }, { status: 422 });

  const allowed = ['title_ar', 'body_ar', 'excerpt_ar', 'image_url', 'tags', 'teams', 'category', 'featured', 'published'];
  const updates = Object.entries(fields).filter(([k]) => allowed.includes(k));
  if (updates.length === 0) return NextResponse.json({ error: 'No valid fields to update' }, { status: 422 });

  const setClauses = updates.map(([k]) => `${k} = ?`).join(', ');
  const args = [...updates.map(([, v]) => v), slug];

  try {
    const result = await dbGet<any>('SELECT id FROM articles WHERE slug = ?', [slug]);
    if (!result) return NextResponse.json({ error: 'Article not found' }, { status: 404 });

    await (await import('@/lib/db')).dbRun(
      `UPDATE articles SET ${setClauses} WHERE slug = ?`,
      args
    );

    return NextResponse.json({ success: true, slug });
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}
