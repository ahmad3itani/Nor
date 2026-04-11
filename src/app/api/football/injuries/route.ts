import { NextResponse } from 'next/server';
import { footballApi, getCurrentSeason } from '@/lib/football-api';

export const revalidate = 1800; // 30 minutes

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const league = searchParams.get('league');
  const team = searchParams.get('team');
  const season = searchParams.get('season') || getCurrentSeason();

  try {
    const data = await footballApi.getInjuries(league || undefined, season);
    const normalized = (data || []).map((entry: any) => ({
      player_id: entry.player?.id || null,
      player_name: entry.player?.name || 'لاعب غير محدد',
      player_photo: entry.player?.photo || '/favicon.ico',
      team_id: entry.team?.id || null,
      team_name: entry.team?.name || 'فريق غير محدد',
      team_logo: entry.team?.logo || null,
      league_id: entry.league?.id || null,
      league_name: entry.league?.name || null,
      type: entry.player?.type || entry.type || 'Injury',
      injury_reason: entry.player?.reason || entry.reason || null,
      fixture_date: entry.fixture?.date || null,
    }));

    const filtered = team
      ? normalized.filter((item: any) => item.team_id?.toString() === team)
      : normalized;

    return NextResponse.json(filtered);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
