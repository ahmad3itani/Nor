import Parser from 'rss-parser';
import { db } from './db';

const parser = new Parser({
  customFields: {
    item: [
      ['media:content', 'mediaContent', { keepArray: false }],
      ['media:thumbnail', 'mediaThumbnail', { keepArray: false }],
      ['enclosure', 'enclosure', { keepArray: false }],
    ],
  },
});

const RSS_FEEDS = [
  { source: "Sky Sports",    url: "https://www.skysports.com/rss/12040" },
  { source: "BBC Sport",     url: "https://feeds.bbci.co.uk/sport/football/rss.xml" },
  { source: "ESPN FC",       url: "https://www.espn.com/espn/rss/soccer/news" },
  { source: "Goal",          url: "https://www.goal.com/feeds/en/news" },
  { source: "90min",         url: "https://www.90min.com/posts.rss" },
  { source: "The Guardian",  url: "https://www.theguardian.com/football/rss" },
  { source: "Fabrizio Romano", url: "https://fabrizioromano.substack.com/feed" },
];

function extractImage(item: any): string | undefined {
  if (item.mediaContent?.['$']?.url) return item.mediaContent['$'].url;
  if (typeof item.mediaContent === 'string' && item.mediaContent.startsWith('http')) return item.mediaContent;
  if (item.mediaThumbnail?.['$']?.url) return item.mediaThumbnail['$'].url;
  if (item.enclosure?.url && item.enclosure?.type?.startsWith('image')) return item.enclosure.url;

  const html = item['content:encoded'] || item.content || item.summary || '';
  const match = html.match(/<img[^>]+src=["']([^"']+)["']/i);
  if (match?.[1] && match[1].startsWith('http')) return match[1];

  if (item['itunes:image']?.['$']?.href) return item['itunes:image']['$'].href;
  return undefined;
}

export { RSS_FEEDS };

export async function fetchNewRssItems(feedOverrides: Record<string, boolean> = {}) {
  const newItems = [];

  for (const feedConfig of RSS_FEEDS) {
    // If the feed has an explicit override set to false, skip it
    if (feedOverrides[feedConfig.source] === false) continue;
    try {
      const feed = await parser.parseURL(feedConfig.url);

      for (const item of feed.items || []) {
        const url = item.link || item.guid;
        if (!url) continue;

        const result = await db.execute({ sql: 'SELECT url FROM rss_seen WHERE url = ?', args: [url] });
        if (result.rows.length === 0) {
          newItems.push({
            title: item.title || '',
            content: item.contentSnippet || item.content || item.title || '',
            url,
            source: feedConfig.source,
            image: extractImage(item),
          });
        }
      }
    } catch (error) {
      console.error(`Failed to fetch RSS from ${feedConfig.source}:`, error);
    }
  }

  return newItems;
}

export async function markRssItemSeen(url: string) {
  await db.execute({ sql: 'INSERT OR IGNORE INTO rss_seen (url) VALUES (?)', args: [url] });
}
