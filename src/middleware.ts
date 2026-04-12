import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { verifySessionToken, COOKIE_NAME } from '@/lib/auth';

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  if (!pathname.startsWith('/admin')) return NextResponse.next();

  // Login page — always accessible, just mark as admin route
  if (pathname === '/admin/login') {
    const res = NextResponse.next();
    res.headers.set('x-is-admin', '1');
    return res;
  }

  // Check session cookie
  const token = request.cookies.get(COOKIE_NAME)?.value;
  if (token && await verifySessionToken(token)) {
    const res = NextResponse.next();
    res.headers.set('x-is-admin', '1');
    return res;
  }

  // Not authenticated — redirect to login
  const loginUrl = request.nextUrl.clone();
  loginUrl.pathname = '/admin/login';
  loginUrl.searchParams.set('next', pathname);
  return NextResponse.redirect(loginUrl);
}

export const config = {
  matcher: ['/admin/:path*'],
};
