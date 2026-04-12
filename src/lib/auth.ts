/**
 * Stateless session auth using HMAC-SHA256.
 * Works in both Edge (middleware) and Node (API routes).
 *
 * Required env vars:
 *   ADMIN_PASSWORD     — the admin login password
 *   ADMIN_SESSION_SECRET — random 32+ char secret for signing tokens
 */

export const COOKIE_NAME = 'gadmin_session';
const SESSION_DAYS = 30;

function getSecret(): string {
  const s = process.env.ADMIN_SESSION_SECRET;
  if (!s) throw new Error('ADMIN_SESSION_SECRET is not set');
  return s;
}

async function importKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign', 'verify']
  );
}

function b64url(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf);
  let binary = '';
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

function fromB64url(s: string): Uint8Array {
  const padded = s.replace(/-/g, '+').replace(/_/g, '/').padEnd(s.length + (4 - s.length % 4) % 4, '=');
  return Uint8Array.from(atob(padded), c => c.charCodeAt(0));
}

export async function createSessionToken(): Promise<string> {
  const payloadBytes = new TextEncoder().encode(JSON.stringify({ ts: Date.now(), v: 1 }));
  const payload = b64url(payloadBytes.buffer as ArrayBuffer);
  const key = await importKey(getSecret());
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(payload));
  return `${payload}.${b64url(sig)}`;
}

export async function verifySessionToken(token: string): Promise<boolean> {
  try {
    const dot = token.lastIndexOf('.');
    if (dot < 1) return false;

    const payload = token.slice(0, dot);
    const sig = token.slice(dot + 1);

    const key = await importKey(getSecret());

    // Constant-time verification
    const sigBytes = fromB64url(sig).buffer as ArrayBuffer;
    const valid = await crypto.subtle.verify('HMAC', key, sigBytes, new TextEncoder().encode(payload));
    if (!valid) return false;

    const data = JSON.parse(new TextDecoder().decode(fromB64url(payload)));
    const ageMs = Date.now() - data.ts;
    return ageMs > 0 && ageMs < SESSION_DAYS * 86_400_000;
  } catch {
    return false;
  }
}

/**
 * Use this in every admin API route to check either:
 *  1. A valid session cookie (browser requests from the admin UI), or
 *  2. A Bearer ADMIN_SECRET header (server-to-server / scripts)
 */
export async function isAdminRequest(req: { cookies: { get: (n: string) => { value: string } | undefined }; headers: { get: (n: string) => string | null } }): Promise<boolean> {
  // 1. Session cookie
  const token = req.cookies.get(COOKIE_NAME)?.value;
  if (token && await verifySessionToken(token)) return true;

  // 2. Bearer ADMIN_SECRET fallback (server-to-server)
  const adminSecret = process.env.ADMIN_SECRET;
  if (adminSecret) {
    const auth = req.headers.get('authorization') || '';
    if (auth === `Bearer ${adminSecret}`) return true;
  }

  return false;
}

export function verifyPassword(input: string): boolean {
  const expected = process.env.ADMIN_PASSWORD || process.env.ADMIN_PASS;
  if (!expected) return false;
  // Constant-time compare to prevent timing attacks
  if (input.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < input.length; i++) {
    diff |= input.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}
