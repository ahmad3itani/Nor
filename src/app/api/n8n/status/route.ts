import { NextRequest, NextResponse } from 'next/server';
import { dbGet } from '@/lib/db';

function authenticate(req: NextRequest): boolean {
  const secret = process.env.N8N_WEBHOOK_SECRET;
  if (!secret) return false;
  const auth = req.headers.get('authorization') || '';
  if (auth.startsWith('Bearer ')) return auth.slice(7) === secret;
  return new URL(req.url).searchParams.get('secret') === secret;
}

/**
 * GET /api/n8n/status
 * Health check for n8n — returns DB stats and last pipeline run.
 * Protected by N8N_WEBHOOK_SECRET.
 */
export async function GET(req: NextRequest) {
  if (!authenticate(req)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const [articleCount, lastRun] = await Promise.all([
      dbGet<{ count: number }>('SELECT COUNT(*) as count FROM articles WHERE published = 1'),
      dbGet<{ pipeline_name: string; status: string; processed_count: number; started_at: string }>(
        'SELECT pipeline_name, status, processed_count, started_at FROM pipeline_runs ORDER BY started_at DESC LIMIT 1'
      ),
    ]);

    return NextResponse.json({
      ok: true,
      articles: articleCount?.count ?? 0,
      lastPipeline: lastRun ?? null,
      timestamp: new Date().toISOString(),
    });
  } catch (err: any) {
    return NextResponse.json({ ok: false, error: err.message }, { status: 500 });
  }
}
