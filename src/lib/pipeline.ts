import { fetchNewRssItems, markRssItemSeen } from './rss-listener';
import { rewriteArticle } from './openrouter';
import { db, ensureOperationalTables } from './db';
import crypto from 'crypto';

function generateSlug(source: string, titleStr: string) {
  const hash = crypto.createHash('md5').update(titleStr).digest('hex').substring(0, 6);
  return `${source.toLowerCase().replace(/[^a-z0-9]/g, '-')}-${hash}`;
}

async function getConfig(): Promise<{
  paused: boolean;
  maxPerRun: number;
  maxPerDay: number;
  feedOverrides: Record<string, boolean>;
}> {
  try {
    const rows = await db.execute({ sql: 'SELECT key, value FROM pipeline_config', args: [] });
    const cfg: Record<string, string> = {};
    for (const row of rows.rows as any[]) cfg[row.key] = row.value;

    return {
      paused: cfg.paused === 'true',
      maxPerRun: Math.max(1, parseInt(cfg.max_per_run || '10', 10)),
      maxPerDay: Math.max(1, parseInt(cfg.max_per_day || '50', 10)),
      feedOverrides: JSON.parse(cfg.feed_overrides || '{}'),
    };
  } catch {
    return { paused: false, maxPerRun: 10, maxPerDay: 50, feedOverrides: {} };
  }
}

async function getTodayCount(): Promise<number> {
  try {
    const result = await db.execute({
      sql: `SELECT COUNT(*) as count FROM articles WHERE created_at >= date('now')`,
      args: [],
    });
    return (result.rows[0] as any)?.count ?? 0;
  } catch {
    return 0;
  }
}

export async function runNewsPipeline() {
  await ensureOperationalTables();

  const config = await getConfig();

  if (config.paused) {
    console.log('⏸ Pipeline is paused. Skipping.');
    return { newItemsFound: 0, processedCount: 0, skipped: true, reason: 'paused' };
  }

  const todayCount = await getTodayCount();
  if (todayCount >= config.maxPerDay) {
    console.log(`🚫 Daily limit reached (${todayCount}/${config.maxPerDay}). Skipping.`);
    return { newItemsFound: 0, processedCount: 0, skipped: true, reason: 'daily_limit', todayCount, maxPerDay: config.maxPerDay };
  }

  const remaining = config.maxPerDay - todayCount;
  const runLimit = Math.min(config.maxPerRun, remaining);

  console.log(`🔄 Starting news pipeline... (limit: ${runLimit}, today: ${todayCount}/${config.maxPerDay})`);

  const runResult = await db.execute({
    sql: `INSERT INTO pipeline_runs (pipeline_name, status) VALUES (?, ?)`,
    args: ['news', 'running'],
  });
  const runId = runResult.lastInsertRowid;

  const newItems = await fetchNewRssItems(config.feedOverrides);
  console.log(`Found ${newItems.length} new RSS items.`);

  let processed = 0;
  try {
    for (const item of newItems) {
      if (processed >= runLimit) break;

      try {
        console.log(`Processing: [${item.source}] ${item.title}`);
        const result = await rewriteArticle(item.title, item.content);
        const slug = generateSlug(item.source, item.url);

        await db.execute({
          sql: `INSERT INTO articles (slug, title_ar, body_ar, excerpt_ar, source_url, source, tags, teams, category, image_url)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          args: [slug, result.title_ar, result.body_ar, result.excerpt_ar ?? null, item.url, item.source, result.tags, result.teams ?? null, result.category ?? 'general', item.image || null],
        });

        await markRssItemSeen(item.url);
        console.log(`✅ Saved article: ${result.title_ar}`);
        processed++;
      } catch (err) {
        console.error(`Failed to process item: ${item.url}`, err);
      }
    }

    await db.execute({
      sql: `UPDATE pipeline_runs
            SET status = ?, new_items_found = ?, processed_count = ?, finished_at = datetime('now')
            WHERE id = ?`,
      args: ['completed', newItems.length, processed, runId ?? 0],
    });
  } catch (error: any) {
    await db.execute({
      sql: `UPDATE pipeline_runs
            SET status = ?, new_items_found = ?, processed_count = ?, error_message = ?, finished_at = datetime('now')
            WHERE id = ?`,
      args: ['failed', newItems.length, processed, error.message, runId ?? 0],
    });
    throw error;
  }

  return { newItemsFound: newItems.length, processedCount: processed };
}
