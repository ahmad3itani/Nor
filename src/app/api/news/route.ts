import { NextResponse } from 'next/server';
import { db } from '@/lib/db';

export const revalidate = 60; // 1 min

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const q = searchParams.get('q')?.trim() || '';
    const source = searchParams.get('source')?.trim() || '';
    const category = searchParams.get('category')?.trim() || '';
    const featuredOnly = searchParams.get('featured') === '1';
    const limit = Math.min(parseInt(searchParams.get('limit') || '10', 10), 50);
    const offset = Math.max(parseInt(searchParams.get('offset') || '0', 10), 0);

    const conditions: string[] = ['published = 1'];
    const args: (string | number)[] = [];

    if (q) {
      conditions.push('(title_ar LIKE ? OR body_ar LIKE ?)');
      args.push(`%${q}%`, `%${q}%`);
    }
    if (source) {
      conditions.push('source = ?');
      args.push(source);
    }
    if (category) {
      conditions.push('category = ?');
      args.push(category);
    }
    if (featuredOnly) {
      conditions.push('featured = 1');
    }

    const whereClause = `WHERE ${conditions.join(' AND ')}`;

    const [articlesResult, totalResult, sourcesResult] = await Promise.all([
      db.execute({
        sql: `SELECT * FROM articles ${whereClause} ORDER BY created_at DESC LIMIT ? OFFSET ?`,
        args: [...args, limit, offset],
      }),
      db.execute({
        sql: `SELECT COUNT(*) as count FROM articles ${whereClause}`,
        args,
      }),
      db.execute({
        sql: `SELECT source, COUNT(*) as count FROM articles WHERE published = 1 GROUP BY source ORDER BY count DESC, source ASC`,
        args: [],
      }),
    ]);

    const articles = articlesResult.rows;
    const total = (totalResult.rows[0] as any)?.count ?? 0;
    const sources = sourcesResult.rows;

    return NextResponse.json({
      items: articles,
      total,
      sources,
      limit,
      offset,
      hasMore: offset + articles.length < total,
    });
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}
