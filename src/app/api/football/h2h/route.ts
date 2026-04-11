import { NextResponse } from 'next/server';
import { footballApi } from '@/lib/football-api';

export const revalidate = 86400; // 24 hours

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const team1 = searchParams.get('team1');
  const team2 = searchParams.get('team2');

  if (!team1 || !team2) {
    return NextResponse.json({ error: 'team1 and team2 parameters required' }, { status: 400 });
  }

  try {
    const h2h = `${team1}-${team2}`;
    const data = await footballApi.getHeadToHead(h2h);
    return NextResponse.json(data);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
