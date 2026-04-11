import { NextResponse } from 'next/server';
import { footballApi } from '@/lib/football-api';

export const revalidate = 86400; // 24 hours

export async function GET(request: Request, { params }: { params: { id: string } }) {
  try {
    const data = await footballApi.getCoachDetails(params.id);
    return NextResponse.json(data);
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
