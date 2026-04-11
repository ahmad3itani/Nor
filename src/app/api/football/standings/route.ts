import { NextResponse } from 'next/server';
import { footballApi, getCurrentSeason } from '@/lib/football-api';

export const revalidate = 3600; // 1 hour

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const league = searchParams.get('league') || '39'; // Default Premier League
  const season = searchParams.get('season') || getCurrentSeason();

  try {
    const standings = await footballApi.getStandings(league, season);
    return NextResponse.json(standings);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
