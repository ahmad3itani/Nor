# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
npm run dev       # Start development server on localhost:3000
npm run build     # Build for production
npm run lint      # Run ESLint
```

**Database initialization** (run once before first use):
```bash
npx tsx scripts/init-db.ts
```

**Test scripts** (run with tsx):
```bash
npx tsx scripts/test-pipeline.ts   # Test the news pipeline manually
npx tsx scripts/seed-mock-news.ts  # Seed mock articles into the DB
npx tsx scripts/test-season.ts     # Test season logic
```

There are no automated tests.

## Architecture

"Nor" (نور) is an Arabic-language football news and analytics platform. The UI is fully RTL (`dir="rtl"`), and all user-facing text is in Arabic.

### Data flow

1. **RSS → AI → SQLite**: Vercel cron at `/api/cron/rss` (every 10 min) calls `lib/pipeline.ts`, which fetches new RSS items via `lib/rss-listener.ts`, rewrites them in Arabic using OpenRouter/Claude via `lib/openrouter.ts`, and stores the result in `data/nor.db`.

2. **Live scores**: Vercel cron at `/api/cron/scores` (every 2 min) polls the API-Football v3 REST API (`lib/football-api.ts`) and caches responses in the `api_cache` table.

3. **SQLite database** (`data/nor.db`): A single `better-sqlite3` file, initialized by `lib/db.ts`. Tables: `articles`, `rss_seen`, `match_results`, `match_events`, `match_statistics`, `player_season_stats`, `team_season_stats`, `transfers`, `injuries`, `odds_history`, `standings_snapshots`, `api_cache`, `pipeline_runs`.

### Key environment variables

- `API_FOOTBALL_KEY` — RapidAPI key for api-football-v1.p.rapidapi.com
- `API_FOOTBALL_HOST` — defaults to `api-football-v1.p.rapidapi.com`
- `OPENROUTER_API_KEY` — for AI article rewriting
- `OPENROUTER_MODEL` — defaults to `anthropic/claude-3.5-sonnet`
- `CRON_SECRET` — Bearer token required by cron route handlers

### Frontend patterns

- **Next.js App Router** (v14) with all pages under `src/app/`
- **React Query** (`@tanstack/react-query`) for client-side data fetching, configured in `src/components/providers/Providers.tsx`
- **Favorites** and **reminders** are stored in `localStorage` (not the DB), managed by `src/hooks/useFavorites.ts` and `src/hooks/useReminders.ts`
- **League configuration** is centralized in `src/lib/config/leagues.ts` — all supported leagues (Top 5 European, Arab, Continental, etc.) with their API-Football IDs live here

### API routes

All football data routes live under `/api/football/` and proxy to the API-Football v3 API. The `/api/cron/*` routes are protected by `CRON_SECRET` bearer auth. The `/api/news/*` routes read from SQLite.

### Styling

Tailwind CSS with RTL support (`tailwindcss-rtl`). The layout uses a custom dark theme (`bg-nor-black`, `text-nor-white`). The HTML root is always `lang="ar" dir="rtl" class="dark"`.
