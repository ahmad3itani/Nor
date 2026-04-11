import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

/**
 * Protect /admin/* pages with HTTP Basic Auth.
 * Set ADMIN_USER and ADMIN_PASS in your environment variables.
 * Falls back to ADMIN_SECRET as the password if ADMIN_PASS is not set.
 */
export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Only protect admin routes
  if (!pathname.startsWith('/admin')) {
    return NextResponse.next();
  }

  const adminUser = process.env.ADMIN_USER || 'admin';
  const adminPass = process.env.ADMIN_PASS || process.env.ADMIN_SECRET;

  // If no password is configured, block access entirely in production
  if (!adminPass) {
    if (process.env.NODE_ENV === 'production') {
      return new NextResponse('Admin access is not configured.', { status: 503 });
    }
    return NextResponse.next(); // Allow in dev without config
  }

  const authHeader = request.headers.get('authorization');

  if (authHeader) {
    const [scheme, encoded] = authHeader.split(' ');
    if (scheme === 'Basic' && encoded) {
      const decoded = Buffer.from(encoded, 'base64').toString('utf-8');
      const [user, pass] = decoded.split(':');
      if (user === adminUser && pass === adminPass) {
        return NextResponse.next();
      }
    }
  }

  // Prompt for Basic Auth credentials
  return new NextResponse('Authentication required', {
    status: 401,
    headers: {
      'WWW-Authenticate': 'Basic realm="Nor Admin", charset="UTF-8"',
    },
  });
}

export const config = {
  matcher: ['/admin/:path*'],
};
