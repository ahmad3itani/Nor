'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';

const NAV = [
  { href: '/admin',           label: 'لوحة التحكم', icon: '⊞', exact: true },
  { href: '/admin/articles',  label: 'المقالات',    icon: '📰' },
  { href: '/admin/articles/new', label: 'مقال جديد', icon: '+' },
  { href: '/admin/settings',  label: 'الإعدادات',   icon: '⚙' },
  { href: '/admin/news',      label: 'خط الأخبار',  icon: '◈' },
];

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();

  async function handleLogout() {
    await fetch('/api/admin/auth/logout', { method: 'POST' });
    router.replace('/admin/login');
  }

  function isActive(href: string, exact?: boolean) {
    if (exact) return pathname === href;
    // Don't highlight /admin for sub-routes
    if (href === '/admin') return pathname === '/admin';
    return pathname.startsWith(href);
  }

  return (
    <div className="min-h-screen flex" dir="rtl">
      {/* Sidebar */}
      <aside className="w-56 flex-shrink-0 bg-[#0a0a0a] border-l border-neutral-800/60 flex flex-col fixed right-0 top-0 h-full z-40">
        {/* Brand */}
        <div className="h-14 flex items-center gap-2 px-5 border-b border-neutral-800/60">
          <div className="w-7 h-7 rounded-lg bg-nor-green/10 border border-nor-green/20 flex items-center justify-center flex-shrink-0">
            <span className="font-readex text-nor-green font-bold text-xs">G</span>
          </div>
          <div>
            <p className="font-readex text-white text-sm font-bold leading-none">Goaliador</p>
            <p className="font-readex text-neutral-500 text-xs">Admin</p>
          </div>
        </div>

        {/* Nav */}
        <nav className="flex-1 p-3 space-y-0.5 overflow-y-auto">
          {NAV.map(({ href, label, icon, exact }) => (
            <Link
              key={href}
              href={href}
              className={`flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-readex transition-colors ${
                isActive(href, exact)
                  ? 'bg-nor-green/10 text-nor-green font-medium'
                  : 'text-neutral-400 hover:text-white hover:bg-neutral-800/60'
              }`}
            >
              <span className="text-sm w-5 text-center opacity-70">{icon}</span>
              {label}
            </Link>
          ))}
        </nav>

        {/* Footer */}
        <div className="p-3 border-t border-neutral-800/60 space-y-0.5">
          <Link
            href="/"
            target="_blank"
            className="flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-readex text-neutral-500 hover:text-white hover:bg-neutral-800/60 transition-colors"
          >
            <span className="text-sm w-5 text-center opacity-70">↗</span>
            عرض الموقع
          </Link>
          <button
            onClick={handleLogout}
            className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-readex text-red-400/70 hover:text-red-400 hover:bg-red-950/30 transition-colors"
          >
            <span className="text-sm w-5 text-center">⏻</span>
            تسجيل الخروج
          </button>
        </div>
      </aside>

      {/* Main — offset for fixed sidebar (56 = w-56 = 224px) */}
      <main className="flex-1 mr-56 min-w-0 bg-nor-black min-h-screen">
        {/* Top bar */}
        <div className="h-14 border-b border-neutral-800/60 flex items-center px-6 sticky top-0 bg-nor-black/90 backdrop-blur-sm z-30">
          <p className="font-readex text-neutral-300 text-sm">
            {NAV.find(n => isActive(n.href, n.exact))?.label || 'Admin'}
          </p>
        </div>
        <div className="p-6">
          {children}
        </div>
      </main>
    </div>
  );
}
