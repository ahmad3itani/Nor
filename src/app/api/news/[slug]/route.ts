import { NextResponse } from 'next/server';
import { dbGet } from '@/lib/db';

export const revalidate = 300; // 5 min

export async function GET(_request: Request, { params }: { params: { slug: string } }) {
  try {
    const article = await dbGet('SELECT * FROM articles WHERE slug = ?', [params.slug]);
    if (!article) return new Response('Not found', { status: 404 });
    return NextResponse.json(article);
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}
