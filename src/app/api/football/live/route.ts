import { NextResponse } from 'next/server';
import { footballApi } from '@/lib/football-api';
import { filterSupportedLeagueFixtures, sortFixtures } from '@/lib/fixtures';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

export async function GET() {
  try {
    const liveMatches = await footballApi.getLiveMatches();
    return NextResponse.json(sortFixtures(filterSupportedLeagueFixtures(liveMatches)));
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
