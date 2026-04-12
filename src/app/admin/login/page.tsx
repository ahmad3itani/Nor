'use client';

import { useState, useRef } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense } from 'react';

function LoginForm() {
  const router = useRouter();
  const params = useSearchParams();
  const next = params.get('next') || '/admin';

  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!password) return;

    setLoading(true);
    setError('');

    try {
      const res = await fetch('/api/admin/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password }),
      });

      if (res.ok) {
        router.replace(next);
      } else {
        const data = await res.json();
        setError(data.error || 'كلمة المرور غير صحيحة');
        setPassword('');
        inputRef.current?.focus();
      }
    } catch {
      setError('حدث خطأ، حاول مجدداً');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen bg-nor-black flex items-center justify-center p-4">
      <div className="w-full max-w-sm">
        {/* Logo */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-14 h-14 rounded-2xl bg-nor-green/10 border border-nor-green/20 mb-4">
            <svg xmlns="http://www.w3.org/2000/svg" className="w-7 h-7 text-nor-green" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z" />
            </svg>
          </div>
          <h1 className="font-readex text-white text-2xl font-bold">لوحة تحكم Goaliador</h1>
          <p className="text-neutral-500 text-sm font-readex mt-1">أدخل كلمة المرور للمتابعة</p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <input
              ref={inputRef}
              type="password"
              value={password}
              onChange={e => setPassword(e.target.value)}
              placeholder="كلمة المرور"
              dir="ltr"
              autoFocus
              autoComplete="current-password"
              className="w-full bg-neutral-900 border border-neutral-800 rounded-xl px-4 py-3 text-white text-center text-lg tracking-widest focus:border-nor-green outline-none transition-colors placeholder:text-neutral-600 placeholder:tracking-normal"
            />
          </div>

          {error && (
            <div className="bg-red-950/50 border border-red-900 rounded-xl px-4 py-3 text-center">
              <p className="text-red-400 text-sm font-readex">{error}</p>
            </div>
          )}

          <button
            type="submit"
            disabled={loading || !password}
            className="w-full py-3 rounded-xl bg-nor-green text-black font-readex font-bold text-base disabled:opacity-50 hover:bg-nor-green/90 transition-colors"
          >
            {loading ? '...' : 'دخول'}
          </button>
        </form>
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense>
      <LoginForm />
    </Suspense>
  );
}
