/**
 * Database client — Turso (libsql) for production, local SQLite file for dev.
 *
 * Set these environment variables:
 *   TURSO_DATABASE_URL  — "libsql://your-db.turso.io" in prod, "file:data/nor.db" in dev
 *   TURSO_AUTH_TOKEN    — Turso auth token (only needed for remote URL)
 *
 * For local dev without Turso, just set:
 *   TURSO_DATABASE_URL=file:data/nor.db   (or leave unset — defaults to this)
 */
import { createClient } from '@libsql/client';
import path from 'path';
import fs from 'fs';

// Ensure local data dir exists (no-op on Vercel/Turso)
const dbUrl = process.env.TURSO_DATABASE_URL || `file:${path.join(process.cwd(), 'data', 'nor.db')}`;
if (dbUrl.startsWith('file:')) {
  const dataDir = path.join(process.cwd(), 'data');
  if (!fs.existsSync(dataDir)) {
    fs.mkdirSync(dataDir, { recursive: true });
  }
}

export const db = createClient({
  url: dbUrl,
  authToken: process.env.TURSO_AUTH_TOKEN,
});

// ── Typed query helpers ───────────────────────────────────────────────────────

export async function dbGet<T = Record<string, unknown>>(
  sql: string,
  args: (string | number | null)[] = []
): Promise<T | undefined> {
  const result = await db.execute({ sql, args });
  if (result.rows.length === 0) return undefined;
  return result.rows[0] as unknown as T;
}

export async function dbAll<T = Record<string, unknown>>(
  sql: string,
  args: (string | number | null)[] = []
): Promise<T[]> {
  const result = await db.execute({ sql, args });
  return result.rows as unknown as T[];
}

export async function dbRun(
  sql: string,
  args: (string | number | null | bigint)[] = []
): Promise<{ lastInsertRowid: bigint | undefined; rowsAffected: number }> {
  const result = await db.execute({ sql, args: args as any });
  return { lastInsertRowid: result.lastInsertRowid, rowsAffected: result.rowsAffected };
}

// ── Schema initialisation ─────────────────────────────────────────────────────

const SCHEMA_STATEMENTS = [
  `CREATE TABLE IF NOT EXISTS articles (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    slug        TEXT UNIQUE NOT NULL,
    title_ar    TEXT NOT NULL,
    body_ar     TEXT NOT NULL,
    excerpt_ar  TEXT,
    source_url  TEXT NOT NULL,
    source      TEXT NOT NULL,
    tags        TEXT,
    teams       TEXT,
    category    TEXT DEFAULT 'general',
    published   INTEGER DEFAULT 1,
    featured    INTEGER DEFAULT 0,
    views       INTEGER DEFAULT 0,
    image_url   TEXT,
    created_at  TEXT DEFAULT (datetime('now'))
  )`,
  `CREATE TABLE IF NOT EXISTS rss_seen (
    url     TEXT PRIMARY KEY,
    seen_at TEXT DEFAULT (datetime('now'))
  )`,
  `CREATE TABLE IF NOT EXISTS match_results (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    fixture_id      INTEGER UNIQUE NOT NULL,
    league_id       INTEGER NOT NULL,
    league_name     TEXT NOT NULL,
    home_team_id    INTEGER NOT NULL,
    home_team_name  TEXT NOT NULL,
    away_team_id    INTEGER NOT NULL,
    away_team_name  TEXT NOT NULL,
    home_goals      INTEGER NOT NULL,
    away_goals      INTEGER NOT NULL,
    status          TEXT NOT NULL,
    match_date      TEXT NOT NULL,
    created_at      TEXT DEFAULT (datetime('now'))
  )`,
  `CREATE TABLE IF NOT EXISTS api_cache (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    endpoint   TEXT NOT NULL,
    params     TEXT,
    response   TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    UNIQUE(endpoint, params)
  )`,
  `CREATE TABLE IF NOT EXISTS pipeline_runs (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    pipeline_name    TEXT NOT NULL,
    status           TEXT NOT NULL,
    new_items_found  INTEGER DEFAULT 0,
    processed_count  INTEGER DEFAULT 0,
    error_message    TEXT,
    started_at       TEXT DEFAULT (datetime('now')),
    finished_at      TEXT
  )`,
  `CREATE INDEX IF NOT EXISTS idx_articles_created   ON articles(created_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_articles_published ON articles(published, created_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_articles_category  ON articles(category, created_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_articles_featured  ON articles(featured, created_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_match_results_date ON match_results(match_date)`,
  `CREATE INDEX IF NOT EXISTS idx_pipeline_runs_date ON pipeline_runs(started_at DESC)`,
];

export async function initDb() {
  await db.batch(SCHEMA_STATEMENTS.map(sql => ({ sql, args: [] })));
}

export async function ensureOperationalTables() {
  await db.batch([
    { sql: `CREATE TABLE IF NOT EXISTS pipeline_runs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      pipeline_name TEXT NOT NULL,
      status TEXT NOT NULL,
      new_items_found INTEGER DEFAULT 0,
      processed_count INTEGER DEFAULT 0,
      error_message TEXT,
      started_at TEXT DEFAULT (datetime('now')),
      finished_at TEXT
    )`, args: [] },
    { sql: `CREATE INDEX IF NOT EXISTS idx_pipeline_runs_started_at ON pipeline_runs(started_at DESC)`, args: [] },
  ]);
}

export default db;
