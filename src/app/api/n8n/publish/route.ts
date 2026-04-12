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

function authenticate(req: NextRequest): boolean {
  const secret = process.env.N8N_WEBHOOK_SECRET;
  if (!secret) return false;

  const auth = req.headers.get('authorization') || '';
  if (auth.startsWith('Bearer ')) {
    return auth.slice(7) === secret;
  }
  const qSecret = new URL(req.url).searchParams.get('secret');
  return qSecret === secret;
}

export async function POST(req: NextRequest) {
  if (!authenticate(req)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  }

  const title = typeof body.title === 'string' ? body.title.trim() : '';
  const content = typeof body.content === 'string' ? body.content.trim() : '';
  const source = typeof body.source === 'string' ? body.source.trim() : 'n8n';
  const sourceUrl = typeof body.source_url === 'string' ? body.source_url.trim() : '';

  if (!title || !content) {
    return NextResponse.json({ error: 'title and content are required' }, { status: 422 });
  }

  const imageUrl = typeof body.image_url === 'string' ? body.image_url.trim() : null;
  const excerpt = typeof body.excerpt === 'string' ? body.excerpt.trim() : null;
  const category = typeof body.category === 'string' ? body.category.trim() : 'general';
  const featured = body.featured === true || body.featured === 1 ? 1 : 0;

  const rawTags = body.tags;
  const tagsArray: string[] = Array.isArray(rawTags)
    ? rawTags.filter((t) => typeof t === 'string')
    : typeof rawTags === 'string'
    ? rawTags.split(',').map((t) => t.trim()).filter(Boolean)
    : [];
  const tags = JSON.stringify(tagsArray);

  const rawTeams = body.teams;
  const teamsArray: string[] = Array.isArray(rawTeams)
    ? rawTeams.filter((t) => typeof t === 'string')
    : typeof rawTeams === 'string'
    ? rawTeams.split(',').map((t) => t.trim()).filter(Boolean)
    : [];
  const teams = JSON.stringify(teamsArray);

  const slug =
    typeof body.slug === 'string' && body.slug.trim()
      ? body.slug.trim()
      : generateSlug(title);

  const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL || 'https://goaliador.com';

  const insertSql = `INSERT INTO articles (slug, title_ar, body_ar, excerpt_ar, source_url, source, tags, teams, category, featured, published, image_url)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)`;
  const insertArgs = [slug, title, content, excerpt, sourceUrl, source, tags, teams, category, featured, imageUrl];

  try {
    const result = await db.execute({ sql: insertSql, args: insertArgs });

    return NextResponse.json({
      success: true,
      id: result.lastInsertRowid,
      slug,
      url: `${SITE_URL}/news/${slug}`,
    }, { status: 201 });

  } catch (err: any) {
    if (err?.message?.includes('UNIQUE constraint failed')) {
      const retry = `${slug}-${Math.random().toString(36).slice(2, 6)}`;
      const retryArgs = [retry, ...insertArgs.slice(1)];
      try {
        const result = await db.execute({ sql: insertSql, args: retryArgs });
        return NextResponse.json({
          success: true,
          id: result.lastInsertRowid,
          slug: retry,
          url: `${SITE_URL}/news/${retry}`,
        }, { status: 201 });
      } catch (e2: any) {
        return NextResponse.json({ error: e2.message }, { status: 500 });
      }
    }
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}

export async function GET(req: NextRequest) {
  if (!authenticate(req)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  return NextResponse.json({ status: 'ok', endpoint: '/api/n8n/publish' });
}
