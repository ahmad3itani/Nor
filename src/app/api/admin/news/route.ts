import { NextRequest, NextResponse } from 'next/server';
import { db, ensureOperationalTables } from '@/lib/db';
import { runNewsPipeline } from '@/lib/pipeline';
import { isAdminRequest } from '@/lib/auth';

export async function GET(request: NextRequest) {
  if (!await isAdminRequest(request)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  await ensureOperationalTables();

  try {
    const [articleCountRow, seenCountRow, sourceStats, recentArticles, recentRuns] = await Promise.all([
      db.execute({ sql: `SELECT COUNT(*) as count FROM articles`, args: [] }),
      db.execute({ sql: `SELECT COUNT(*) as count FROM rss_seen`, args: [] }),
      db.execute({ sql: `SELECT source, COUNT(*) as count, MAX(created_at) as latest_created_at FROM articles GROUP BY source ORDER BY count DESC, source ASC`, args: [] }),
      db.execute({ sql: `SELECT id, slug, title_ar, source, created_at FROM articles ORDER BY created_at DESC LIMIT 10`, args: [] }),
      db.execute({ sql: `SELECT * FROM pipeline_runs ORDER BY started_at DESC LIMIT 10`, args: [] }),
    ]);

    return NextResponse.json({
      articleCount: (articleCountRow.rows[0] as any)?.count ?? 0,
      seenCount: (seenCountRow.rows[0] as any)?.count ?? 0,
      sourceStats: sourceStats.rows,
      recentArticles: recentArticles.rows,
      recentRuns: recentRuns.rows,
    });
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  if (!await isAdminRequest(request)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const result = await runNewsPipeline();
    return NextResponse.json({ success: true, result });
  } catch (error: any) {
    return NextResponse.json({ success: false, error: error.message }, { status: 500 });
  }
}
