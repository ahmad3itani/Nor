import { NextResponse } from 'next/server';

export async function GET() {
  const url = process.env.TURSO_DATABASE_URL || 'NOT_SET';
  const token = process.env.TURSO_AUTH_TOKEN || '';

  const SCHEMA = [
    `CREATE TABLE IF NOT EXISTS articles (
      id INTEGER PRIMARY KEY AUTOINCREMENT, slug TEXT UNIQUE NOT NULL,
      title_ar TEXT NOT NULL, body_ar TEXT NOT NULL, excerpt_ar TEXT,
      source_url TEXT NOT NULL, source TEXT NOT NULL, tags TEXT, teams TEXT,
      category TEXT DEFAULT 'general', published INTEGER DEFAULT 1,
      featured INTEGER DEFAULT 0, views INTEGER DEFAULT 0,
      image_url TEXT, created_at TEXT DEFAULT (datetime('now'))
    )`,
    `CREATE TABLE IF NOT EXISTS rss_seen (url TEXT PRIMARY KEY, seen_at TEXT DEFAULT (datetime('now')))`,
    `CREATE TABLE IF NOT EXISTS match_results (
      id INTEGER PRIMARY KEY AUTOINCREMENT, fixture_id INTEGER UNIQUE NOT NULL,
      league_id INTEGER NOT NULL, league_name TEXT NOT NULL,
      home_team_id INTEGER NOT NULL, home_team_name TEXT NOT NULL,
      away_team_id INTEGER NOT NULL, away_team_name TEXT NOT NULL,
      home_goals INTEGER NOT NULL, away_goals INTEGER NOT NULL,
      status TEXT NOT NULL, match_date TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now'))
    )`,
    `CREATE TABLE IF NOT EXISTS api_cache (
      id INTEGER PRIMARY KEY AUTOINCREMENT, endpoint TEXT NOT NULL, params TEXT,
      response TEXT NOT NULL, expires_at TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')), UNIQUE(endpoint, params)
    )`,
    `CREATE TABLE IF NOT EXISTS pipeline_runs (
      id INTEGER PRIMARY KEY AUTOINCREMENT, pipeline_name TEXT NOT NULL,
      status TEXT NOT NULL, new_items_found INTEGER DEFAULT 0,
      processed_count INTEGER DEFAULT 0, error_message TEXT,
      started_at TEXT DEFAULT (datetime('now')), finished_at TEXT
    )`,
    `CREATE INDEX IF NOT EXISTS idx_articles_created ON articles(created_at DESC)`,
    `CREATE INDEX IF NOT EXISTS idx_articles_published ON articles(published, created_at DESC)`,
    `CREATE INDEX IF NOT EXISTS idx_articles_category ON articles(category, created_at DESC)`,
    `CREATE INDEX IF NOT EXISTS idx_articles_views ON articles(views DESC)`,
  ];

  try {
    const { createClient } = await import('@libsql/client');
    const client = createClient({ url, authToken: token });

    for (const sql of SCHEMA) {
      await client.execute({ sql, args: [] });
    }

    const result = await client.execute({ sql: "SELECT name FROM sqlite_master WHERE type='table'", args: [] });
    return NextResponse.json({
      ok: true,
      tables: result.rows.map((r: any) => r.name),
    });
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: e.message });
  }
}
