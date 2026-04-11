import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';

export async function POST(_req: NextRequest, { params }: { params: { slug: string } }) {
  try {
    await db.execute({
      sql: `UPDATE articles SET views = views + 1 WHERE slug = ? AND published = 1`,
      args: [params.slug],
    });
    return NextResponse.json({ ok: true });
  } catch {
    return NextResponse.json({ ok: false }, { status: 500 });
  }
}
