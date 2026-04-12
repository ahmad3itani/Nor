import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';

function generateSlug(title: string): string {
  const base = title
    .replace(/[\u0610-\u061A\u064B-\u065F]/g, '')
    .replace(/[^\u0600-\u06FF\u0750-\u077F\w\s-]/g, '')
    .trim()
    .replace(/\s+/g, '-')
    .toLowerCase()
    .slice(0, 80);
  const suffix = Date.now().toString(36);
  return base ? `${base}-${suffix}` : `article-${suffix}`;
}

function isAuthorized(req: NextRequest): boolean {
  const adminSecret = process.env.ADMIN_SECRET;
  if (!adminSecret) return process.env.NODE_ENV !== 'production';
  const auth = req.headers.get('authorization') || '';
  if (auth.startsWith('Bearer ')) return auth.slice(7) === adminSecret;
  return new URL(req.url).searchParams.get('secret') === adminSecret;
}

export async function GET(req: NextRequest) {
  if (!isAuthorized(req)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const { searchParams } = new URL(req.url);
  const limit = Math.min(parseInt(searchParams.get('limit') || '50', 10), 200);
  const offset = parseInt(searchParams.get('offset') || '0', 10);
  const search = searchParams.get('q')?.trim() || '';

  try {
    const conditions: string[] = [];
    const args: any[] = [];

    if (search) {
      conditions.push('(title_ar LIKE ? OR slug LIKE ? OR source LIKE ?)');
      const like = `%${search}%`;
      args.push(like, like, like);
    }

    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

    const [countResult, rows] = await Promise.all([
      db.execute({ sql: `SELECT COUNT(*) as total FROM articles ${where}`, args }),
      db.execute({
        sql: `SELECT id, slug, title_ar, excerpt_ar, category, featured, published, image_url, source, views, created_at
              FROM articles ${where}
              ORDER BY created_at DESC
              LIMIT ? OFFSET ?`,
        args: [...args, limit, offset],
      }),
    ]);

    return NextResponse.json({
      total: (countResult.rows[0] as any)?.total ?? 0,
      articles: rows.rows,
    });
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}

export async function POST(req: NextRequest) {
  if (!isAuthorized(req)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  let body: Record<string, any>;
  try { body = await req.json(); } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 });
  }

  const title = (body.title_ar as string)?.trim();
  const content = (body.body_ar as string)?.trim();
  if (!title || !content) {
    return NextResponse.json({ error: 'title_ar and body_ar are required' }, { status: 422 });
  }

  const slug = body.slug?.trim() || generateSlug(title);
  const excerpt = body.excerpt_ar?.trim() || null;
  const imageUrl = body.image_url?.trim() || null;
  const category = body.category?.trim() || 'general';
  const featured = body.featured ? 1 : 0;
  const published = body.published !== undefined ? (body.published ? 1 : 0) : 1;
  const source = body.source?.trim() || 'manual';
  const sourceUrl = body.source_url?.trim() || '';
  const tags = JSON.stringify(Array.isArray(body.tags) ? body.tags : []);
  const teams = JSON.stringify(Array.isArray(body.teams) ? body.teams : []);

  try {
    const result = await db.execute({
      sql: `INSERT INTO articles (slug, title_ar, body_ar, excerpt_ar, source_url, source, tags, teams, category, featured, published, image_url)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      args: [slug, title, content, excerpt, sourceUrl, source, tags, teams, category, featured, published, imageUrl],
    });
    return NextResponse.json({ success: true, id: Number(result.lastInsertRowid), slug }, { status: 201 });
  } catch (err: any) {
    if (err?.message?.includes('UNIQUE constraint failed')) {
      return NextResponse.json({ error: 'Slug already exists' }, { status: 409 });
    }
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}
