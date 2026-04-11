/** @type {import('next').NextConfig} */
const nextConfig = {
  // ── Images ────────────────────────────────────────────────────────────────
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: 'media.api-sports.io' },
      { protocol: 'https', hostname: '**.api-sports.io' },
      { protocol: 'https', hostname: 'media.fabrizio-romano.com' },
      { protocol: 'https', hostname: 'e00-marca.uecdn.es' },
      { protocol: 'https', hostname: 'media.zenfs.com' },
      { protocol: 'https', hostname: 'images.unsplash.com' },
      // Allow any HTTPS image (n8n can source images from anywhere)
      { protocol: 'https', hostname: '**' },
    ],
    formats: ['image/avif', 'image/webp'],
    minimumCacheTTL: 3600,
  },

  // ── Security headers ─────────────────────────────────────────────────────
  async headers() {
    // CSP: allow self + inline styles (Tailwind) + images from anywhere HTTPS
    // unsafe-inline needed for Next.js inline scripts (JSON-LD, __NEXT_DATA__)
    const csp = [
      "default-src 'self'",
      "script-src 'self' 'unsafe-inline' 'unsafe-eval'",   // Next.js requires unsafe-eval in dev; tighten in prod if needed
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data: blob: https:",
      "font-src 'self' data:",
      "connect-src 'self' https:",
      "frame-src 'none'",
      "object-src 'none'",
      "base-uri 'self'",
      "form-action 'self'",
      "upgrade-insecure-requests",
    ].join('; ');

    return [
      {
        source: '/(.*)',
        headers: [
          { key: 'X-DNS-Prefetch-Control',      value: 'on' },
          { key: 'X-Content-Type-Options',      value: 'nosniff' },
          { key: 'X-Frame-Options',             value: 'SAMEORIGIN' },
          { key: 'Referrer-Policy',             value: 'strict-origin-when-cross-origin' },
          { key: 'Permissions-Policy',          value: 'camera=(), microphone=(), geolocation=()' },
          { key: 'Strict-Transport-Security',   value: 'max-age=63072000; includeSubDomains; preload' },
          { key: 'Content-Security-Policy',     value: csp },
        ],
      },
      {
        // Prevent caching of API responses by CDN (they have their own staleTime logic)
        source: '/api/(.*)',
        headers: [
          { key: 'Cache-Control', value: 'no-store, max-age=0' },
        ],
      },
    ];
  },

  // ── Redirects ─────────────────────────────────────────────────────────────
  async redirects() {
    return [
      // Legacy slug formats → canonical
      {
        source: '/article/:slug',
        destination: '/news/:slug',
        permanent: true,
      },
    ];
  },

  // ── Native modules ────────────────────────────────────────────────────────
  // better-sqlite3 is only used in local dev scripts, not in the Next.js app
  // @libsql/client handles all DB access in the app
  serverExternalPackages: ['@libsql/client'],

  // ── Compression & output ──────────────────────────────────────────────────
  compress: true,
  poweredByHeader: false,       // Don't expose X-Powered-By: Next.js
  reactStrictMode: true,

  experimental: {
    serverActions: {
      allowedOrigins: [
        'localhost:3000',
        process.env.NEXT_PUBLIC_SITE_URL?.replace(/^https?:\/\//, '') ?? '',
      ].filter(Boolean),
    },
  },
};

export default nextConfig;
