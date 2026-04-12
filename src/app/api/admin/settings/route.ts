import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { RSS_FEEDS } from '@/lib/rss-listener';
import { verifySessionToken, COOKIE_NAME } from '@/lib/auth';

async function isAuthorized(req: NextRequest): Promise<boolean> {
  const token = req.cookies.get(COOKIE_NAME)?.value;
  if (token && await verifySessionToken(token)) return true;
  // Also allow Bearer ADMIN_SECRET for server-to-server calls
  const adminSecret = process.env.ADMIN_SECRET;
  if (adminSecret) {
    const auth = req.headers.get('authorization') || '';
    if (auth === `Bearer ${adminSecret}`) return true;
  }
  return false;
}

export async function GET(req: NextRequest) {
  if (!await isAuthorized(req)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const rows = await db.execute({ sql: 'SELECT key, value FROM pipeline_config', args: [] });
    const cfg: Record<string, string> = {};
    for (const row of rows.rows as any[]) cfg[(row as any).key] = (row as any).value;

    // Today's article count
    const todayResult = await db.execute({
      sql: `SELECT COUNT(*) as count FROM articles WHERE created_at >= date('now')`,
      args: [],
    });
    const todayCount = (todayResult.rows[0] as any)?.count ?? 0;

    return NextResponse.json({
      paused: cfg.paused === 'true',
      maxPerRun: parseInt(cfg.max_per_run || '10', 10),
      maxPerDay: parseInt(cfg.max_per_day || '50', 10),
      feedOverrides: JSON.parse(cfg.feed_overrides || '{}'),
      feeds: RSS_FEEDS.map(f => ({ source: f.source, url: f.url })),
      todayCount,
    });
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}

export async function PATCH(req: NextRequest) {
  if (!await isAuthorized(req)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  let body: Record<string, any>;
  try { body = await req.json(); } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 });
  }

  const updates: { key: string; value: string }[] = [];

  if (typeof body.paused === 'boolean') {
    updates.push({ key: 'paused', value: body.paused ? 'true' : 'false' });
  }
  if (typeof body.maxPerRun === 'number') {
    updates.push({ key: 'max_per_run', value: String(Math.max(1, Math.min(50, body.maxPerRun))) });
  }
  if (typeof body.maxPerDay === 'number') {
    updates.push({ key: 'max_per_day', value: String(Math.max(1, Math.min(500, body.maxPerDay))) });
  }
  if (typeof body.feedOverrides === 'object' && body.feedOverrides !== null) {
    updates.push({ key: 'feed_overrides', value: JSON.stringify(body.feedOverrides) });
  }

  if (updates.length === 0) {
    return NextResponse.json({ error: 'No valid fields' }, { status: 422 });
  }

  try {
    await db.batch(updates.map(u => ({
      sql: `INSERT INTO pipeline_config (key, value, updated_at) VALUES (?, ?, datetime('now'))
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
      args: [u.key, u.value],
    })));
    return NextResponse.json({ success: true });
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}
