import { NextResponse } from 'next/server';
import { dbAll } from '@/lib/db';
import { footballApi } from '@/lib/football-api';

export const revalidate = 300;

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const q = searchParams.get('q')?.trim() || '';

  if (q.length < 2) {
    return NextResponse.json({ teams: [], players: [], news: [] });
  }

  try {
    const [news, teamsResult, playersResult] = await Promise.all([
      dbAll<{ id: number; slug: string; title_ar: string; source: string; created_at: string }>(
        `SELECT id, slug, title_ar, source, created_at
         FROM articles
         WHERE title_ar LIKE ? OR body_ar LIKE ?
         ORDER BY created_at DESC
         LIMIT 5`,
        [`%${q}%`, `%${q}%`]
      ),
      footballApi.searchTeams(q).catch(() => []),
      footballApi.searchPlayers(q).catch(() => []),
    ]);

    const teams = teamsResult.slice(0, 5).map((entry: any) => ({
      id: entry.team.id,
      name: entry.team.name,
      logo: entry.team.logo,
      country: entry.team.country,
    }));

    const players = playersResult.slice(0, 5).map((entry: any) => ({
      id: entry.player.id,
      name: entry.player.name,
      photo: entry.player.photo,
      age: entry.player.age,
      nationality: entry.player.nationality,
      teamName: entry.statistics?.[0]?.team?.name || null,
      teamLogo: entry.statistics?.[0]?.team?.logo || null,
    }));

    return NextResponse.json({ teams, players, news });
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
