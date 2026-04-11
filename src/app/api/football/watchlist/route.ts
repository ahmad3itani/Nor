import { NextResponse } from 'next/server';
import { footballApi, getCurrentSeason } from '@/lib/football-api';

export const revalidate = 300;

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const ids = (searchParams.get('teamIds') || '')
    .split(',')
    .map((id) => id.trim())
    .filter(Boolean)
    .slice(0, 8);
  const season = searchParams.get('season') || getCurrentSeason();

  if (ids.length === 0) {
    return NextResponse.json([]);
  }

  try {
    const fixturesByTeam = await Promise.all(
      ids.map(async (teamId) => {
        const fixtures = await footballApi.getNextTeamFixtures(teamId, season, 4).catch(() => []);
        return {
          teamId,
          fixtures,
        };
      })
    );

    return NextResponse.json(fixturesByTeam);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
