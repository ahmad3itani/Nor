import { NextResponse } from 'next/server';

export async function GET() {
  const url = process.env.TURSO_DATABASE_URL || 'NOT_SET';
  const token = process.env.TURSO_AUTH_TOKEN || '';
  
  try {
    const { createClient } = await import('@libsql/client');
    const client = createClient({ url, authToken: token });
    const result = await client.execute({ sql: "SELECT name FROM sqlite_master WHERE type='table'", args: [] });
    return NextResponse.json({ 
      url: url.slice(0, 60), 
      token_len: token.length,
      tables: result.rows.map((r: any) => r.name) 
    });
  } catch (e: any) {
    return NextResponse.json({ url: url.slice(0, 60), token_len: token.length, error: e.message });
  }
}
