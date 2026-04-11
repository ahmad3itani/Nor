import { NextResponse } from 'next/server';
import { footballApi } from '@/lib/football-api';

export const revalidate = 86400; // 24 hours

export async function GET(request: Request, { params }: { params: { id: string } }) {
  const { searchParams } = new URL(request.url);
  const season = searchParams.get('season') || new Date().getFullYear().toString();

  try {
    const stats = await footballApi.getPlayerStats(params.id, season);
    return NextResponse.json(stats);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
