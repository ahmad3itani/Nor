import { fetchNewRssItems, markRssItemSeen } from './rss-listener';
import { rewriteArticle } from './openrouter';
import { db, ensureOperationalTables } from './db';
import crypto from 'crypto';

function generateSlug(source: string, titleStr: string) {
  const hash = crypto.createHash('md5').update(titleStr).digest('hex').substring(0, 6);
  return `${source.toLowerCase().replace(/[^a-z0-9]/g, '-')}-${hash}`;
}

export async function runNewsPipeline() {
  await ensureOperationalTables();
  console.log('🔄 Starting news pipeline...');

  const runResult = await db.execute({
    sql: `INSERT INTO pipeline_runs (pipeline_name, status) VALUES (?, ?)`,
    args: ['news', 'running'],
  });
  const runId = runResult.lastInsertRowid;

  const newItems = await fetchNewRssItems();
  console.log(`Found ${newItems.length} new RSS items.`);

  let processed = 0;
  try {
    for (const item of newItems) {
      if (processed >= 5) break;

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
