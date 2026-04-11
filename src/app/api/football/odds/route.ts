import { NextResponse } from 'next/server';
import { footballApi } from '@/lib/football-api';

export const revalidate = 300; // 5 minutes

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const fixture = searchParams.get('fixture');
  const live = searchParams.get('live');

  try {
    let data;
    if (live === 'true') {
      data = await footballApi.getOddsLive();
    } else if (fixture) {
      data = await footballApi.getOdds(fixture);
    } else {
      return NextResponse.json({ error: 'fixture or live parameter required' }, { status: 400 });
    }
    return NextResponse.json(data);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
