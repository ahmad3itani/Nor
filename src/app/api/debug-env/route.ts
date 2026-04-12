import { NextResponse } from 'next/server';

export async function GET() {
  const url = process.env.TURSO_DATABASE_URL || 'NOT_SET';
  const token = process.env.TURSO_AUTH_TOKEN ? `SET_len_${process.env.TURSO_AUTH_TOKEN.length}` : 'NOT_SET';
  return NextResponse.json({ TURSO_DATABASE_URL: url.slice(0, 60), TURSO_AUTH_TOKEN: token });
}
