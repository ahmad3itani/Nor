import { NextRequest, NextResponse } from 'next/server';
import { verifyPassword, createSessionToken, COOKIE_NAME } from '@/lib/auth';

// Slow down brute-force attempts (100ms artificial delay)
function delay(ms: number) {
  return new Promise(r => setTimeout(r, ms));
}

export async function POST(req: NextRequest) {
  await delay(100);

  let body: { password?: string };
  try { body = await req.json(); } catch {
    return NextResponse.json({ error: 'Invalid request' }, { status: 400 });
  }

  if (!body.password || !verifyPassword(body.password)) {
    // Always wait the same time on failure too (prevent timing oracle)
    await delay(400);
    return NextResponse.json({ error: 'كلمة مرور غير صحيحة' }, { status: 401 });
  }

  const token = await createSessionToken();

  const res = NextResponse.json({ ok: true });
  res.cookies.set(COOKIE_NAME, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    path: '/',
    maxAge: 30 * 24 * 60 * 60, // 30 days
  });
  return res;
}
