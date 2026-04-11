import { NextResponse } from 'next/server';
import { footballApi } from '@/lib/football-api';

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const fixtureId = searchParams.get('fixture');

  if (!fixtureId) {
    return NextResponse.json({ error: 'Fixture id required' }, { status: 400 });
  }

  try {
    const predictions = await footballApi.getFixturePredictions(fixtureId);
    return NextResponse.json(predictions);
  } catch (error: any) {
    console.error('Predictions API Error:', error);
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
