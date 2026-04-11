import { NextResponse } from 'next/server';
import { footballApi } from '@/lib/football-api';
import { filterSupportedLeagueFixtures, sortFixtures } from '@/lib/fixtures';
import { format } from 'date-fns';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const date = searchParams.get('date') || format(new Date(), 'yyyy-MM-dd');
  const leagueId = searchParams.get('league');

  try {
    const data = sortFixtures(filterSupportedLeagueFixtures(await footballApi.getDailyFixtures(date)));
    
    // If a specific league is requested, filter to that league only
    if (leagueId && leagueId !== 'all') {
      const filtered = data.filter((f: any) => f.league.id.toString() === leagueId);
      return NextResponse.json(filtered);
    }
    
    return NextResponse.json(data);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
