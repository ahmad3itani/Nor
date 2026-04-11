import { NextResponse } from 'next/server';
import { footballApi } from '@/lib/football-api';

export const revalidate = 3600; // 1 hour

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const team = searchParams.get('team');
  const player = searchParams.get('player');

  try {
    let data;
    if (player) {
      data = await footballApi.getPlayerTransfers(player);
    } else if (team) {
      data = await footballApi.getTeamTransfers(team);
    } else {
      data = await footballApi.getTransfers();
    }

    const normalized = (data || []).map((entry: any) => ({
      player_id: entry.player_id || entry.player?.id || null,
      player_name: entry.player_name || entry.player?.name || 'لاعب غير محدد',
      player_photo: entry.player_photo || entry.player?.photo || '/favicon.ico',
      player_position: entry.player_position || entry.player?.position || null,
      transfers: (entry.transfers || []).map((transfer: any) => ({
        ...transfer,
        from: transfer.teams?.out || transfer.from || null,
        to: transfer.teams?.in || transfer.to || null,
      })),
    }));

    return NextResponse.json(normalized);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
