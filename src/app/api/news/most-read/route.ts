import { NextResponse } from 'next/server';
import { db } from '@/lib/db';

export const revalidate = 300; // 5 min

export async function GET() {
  try {
    const result = await db.execute({
      sql: `SELECT id, slug, title_ar, source, image_url, views, created_at
            FROM articles WHERE published = 1
            ORDER BY views DESC, created_at DESC
            LIMIT 5`,
      args: [],
    });
    return NextResponse.json({ items: result.rows });
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}
