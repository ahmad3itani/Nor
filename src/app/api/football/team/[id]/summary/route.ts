import { NextResponse } from 'next/server';
import { footballApi, getCurrentSeason } from '@/lib/football-api';

export const revalidate = 3600;

export async function GET(request: Request, { params }: { params: { id: string } }) {
  const { searchParams } = new URL(request.url);
  const league = searchParams.get('league') || '39';
  const season = searchParams.get('season') || getCurrentSeason();

  try {
    const [detailsData, statsData, fixturesData] = await Promise.all([
      footballApi.getTeamDetails(params.id),
      footballApi.getTeamStats(params.id, league, season),
      footballApi.getTeamFixtures(params.id, season, 5).catch(() => []),
    ]);

    return NextResponse.json({
      details: detailsData?.[0] || null,
      stats: statsData || null,
      fixtures: fixturesData || [],
    });
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
