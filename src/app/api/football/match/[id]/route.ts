import { NextResponse } from 'next/server';
import { footballApi } from '@/lib/football-api';

export const revalidate = 60; // 1 minute (frequent updates for live matches)

export async function GET(request: Request, { params }: { params: { id: string } }) {
  try {
    const data = await footballApi.getFixtureDetails(params.id);
    if (!data || data.length === 0) {
      return NextResponse.json({ error: 'Match not found' }, { status: 404 });
    }
    return NextResponse.json(data[0]); // Return the single match object
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
