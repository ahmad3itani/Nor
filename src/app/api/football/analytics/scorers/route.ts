import { NextResponse } from 'next/server';
import { footballApi, getCurrentSeason } from '@/lib/football-api';

export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const league = searchParams.get('league') || '39'; 
  const season = searchParams.get('season') || getCurrentSeason();

  try {
    const data = await footballApi.getTopScorers(league, season);
    return NextResponse.json(data);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
