import { NextResponse } from 'next/server';
import { footballApi, getCurrentSeason } from '@/lib/football-api';

export const revalidate = 3600;

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const q = searchParams.get('q')?.trim();
  const league = searchParams.get('league') || undefined;
  const season = searchParams.get('season') || getCurrentSeason();

  if (!q || q.length < 2) {
    return NextResponse.json([]);
  }

  try {
    const teams = await footballApi.searchTeams(q, league, season);
    const normalized = teams.slice(0, 8).map((entry: any) => ({
      id: entry.team.id,
      name: entry.team.name,
      logo: entry.team.logo,
      country: entry.team.country,
      founded: entry.team.founded,
      venueName: entry.venue?.name || null,
    }));

    return NextResponse.json(normalized);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
