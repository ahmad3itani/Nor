import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { verifySessionToken, COOKIE_NAME } from '@/lib/auth';

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  if (!pathname.startsWith('/admin')) return NextResponse.next();

  // Login page is always accessible
  if (pathname === '/admin/login') return NextResponse.next();

  // Check session cookie
  const token = request.cookies.get(COOKIE_NAME)?.value;
  if (token && await verifySessionToken(token)) {
    return NextResponse.next();
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
