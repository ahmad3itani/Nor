import { NextResponse } from 'next/server';
import { footballApi } from '@/lib/football-api';
import { db } from '@/lib/db';

const CRON_SECRET = process.env.CRON_SECRET;

export async function GET(request: Request) {
  if (!CRON_SECRET) {
    return NextResponse.json({ error: 'CRON_SECRET is not configured' }, { status: 500 });
  }

  const authHeader = request.headers.get('authorization');
  if (authHeader !== `Bearer ${CRON_SECRET}`) {
    return new Response('Unauthorized', { status: 401 });
  }

  try {
    const liveMatches = await footballApi.getLiveMatches();

    const finishedMatches = liveMatches.filter((m: any) =>
      m.fixture.status.short === 'FT' ||
      m.fixture.status.short === 'AET' ||
      m.fixture.status.short === 'PEN'
    );

    // Ensure table exists
    await db.execute({
      sql: `CREATE TABLE IF NOT EXISTS match_results (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fixture_id INTEGER UNIQUE NOT NULL,
        league_id INTEGER NOT NULL,
        league_name TEXT NOT NULL,
        home_team_id INTEGER NOT NULL,
        home_team_name TEXT NOT NULL,
        away_team_id INTEGER NOT NULL,
        away_team_name TEXT NOT NULL,
        home_goals INTEGER NOT NULL,
        away_goals INTEGER NOT NULL,
        status TEXT NOT NULL,
        match_date TEXT NOT NULL,
        created_at TEXT DEFAULT (datetime('now'))
      )`,
      args: [],
    });

    let savedCount = 0;
    for (const match of finishedMatches) {
      try {
        await db.execute({
          sql: `INSERT OR IGNORE INTO match_results
                (fixture_id, league_id, league_name, home_team_id, home_team_name,
                 away_team_id, away_team_name, home_goals, away_goals, status, match_date)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          args: [
            match.fixture.id,
            match.league.id,
            match.league.name,
            match.teams.home.id,
            match.teams.home.name,
            match.teams.away.id,
            match.teams.away.name,
            match.goals.home,
            match.goals.away,
            match.fixture.status.short,
            match.fixture.date,
          ],
        });
        savedCount++;
      } catch {
        // Ignore duplicates
      }
    }

    return NextResponse.json({
      success: true,
      message: 'Scores revalidation completed',
      liveMatches: liveMatches.length,
      finishedMatches: finishedMatches.length,
      savedMatches: savedCount,
    });
  } catch (error: any) {
    return NextResponse.json({ success: false, error: error.message }, { status: 500 });
  }
}
