import { NextResponse } from 'next/server';
import { generatePunditry } from '@/lib/openrouter';

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const fixtureId = searchParams.get('fixture');

  if (!fixtureId) {
    return NextResponse.json({ error: 'Fixture ID is required' }, { status: 400 });
  }

  try {
    // We could fetch actual events/stats here if we want to pass them to OpenAI!
    // But since API-football credits are tight, we will rely on minimal contextual data passed
    // from the client when calling this API.
    const context = searchParams.get('context') || '';
    
    // Check cache first in production; here we do direct since it's a dynamic user request
    const summary = await generatePunditry(context);
    
    return NextResponse.json({ summary });
  } catch (error: any) {
    console.error('Punditry error:', error);
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
