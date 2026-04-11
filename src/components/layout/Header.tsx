"use client";
import Link from 'next/link';
import { useState } from 'react';
import { usePathname } from 'next/navigation';
import GlobalSearch from './GlobalSearch';

export default function Header() {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [moreMenuOpen, setMoreMenuOpen] = useState(false);
  const pathname = usePathname();

  const primaryLinks = [
    { href: '/', label: 'الرئيسية' },
    { href: '/live', label: 'مباشر' },
    { href: '/news', label: 'الأخبار' },
    { href: '/matches', label: 'المباريات' },
    { href: '/analytics', label: 'الإحصائيات' },
    { href: '/favorites', label: 'المفضلة' },
  ];

  const secondaryLinks = [
    { href: '/watchlist', label: 'المتابعة' },
    { href: '/reminders', label: 'التنبيهات' },
    { href: '/compare/players', label: 'مقارنة اللاعبين' },
    { href: '/compare/teams', label: 'مقارنة الفرق' },
    { href: '/transfers', label: 'الانتقالات' },
    { href: '/injuries', label: 'الإصابات' },
    { href: '/h2h', label: 'المواجهات' },
  ];
  const navLinks = [...primaryLinks, ...secondaryLinks];

  return (
    <header className="sticky top-0 z-40 w-full backdrop-blur flex-none transition-colors duration-500 bg-nor-black/80 border-b border-neutral-800">
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex h-14 items-center justify-between gap-3">
          <Link href="/" className="flex items-center gap-2">
            <span className="font-readex text-xl font-bold tracking-tighter text-nor-green">nōr</span>
            <span className="text-base font-medium text-neutral-500">|</span>
            <span className="font-amiri text-xl text-white">نور</span>
          </Link>

          <nav className="hidden lg:flex items-center gap-4">
            {primaryLinks.map(link => {
              const isActive = link.href === '/' ? pathname === '/' : pathname.startsWith(link.href);
              return (
                <Link
                  key={link.href}
                  href={link.href}
                  className={`text-[13px] font-medium transition-colors ${isActive ? 'text-nor-green' : 'text-neutral-300 hover:text-nor-green'}`}
                >
                  {link.label}
                </Link>
              );
            })}

            <div className="relative">
              <button
                type="button"
                onClick={() => setMoreMenuOpen((value) => !value)}
                className={`inline-flex items-center gap-2 rounded-full border px-3 py-1.5 text-[13px] font-readex transition-colors ${
                  moreMenuOpen || secondaryLinks.some(l => pathname.startsWith(l.href))
                    ? 'border-nor-green bg-nor-green/10 text-nor-green'
                    : 'border-neutral-700 bg-neutral-900/70 text-neutral-300 hover:text-white hover:border-neutral-500'
                }`}
              >
                <span>المزيد</span>
                <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className={`transition-transform ${moreMenuOpen ? 'rotate-180' : ''}`}>
                  <path d="m6 9 6 6 6-6" />
                </svg>
              </button>

              {moreMenuOpen ? (
                <div className="absolute left-0 mt-3 w-56 rounded-2xl border border-neutral-800 bg-neutral-950/95 p-2 shadow-2xl backdrop-blur">
                  {secondaryLinks.map((link) => {
                    const isActive = pathname.startsWith(link.href);
                    return (
                      <Link
                        key={link.href}
                        href={link.href}
                        onClick={() => setMoreMenuOpen(false)}
                        className={`block rounded-xl px-3 py-2 text-sm font-readex transition-colors hover:bg-neutral-900 hover:text-nor-green ${isActive ? 'text-nor-green bg-neutral-900/60' : 'text-neutral-300'}`}
                      >
                        {link.label}
                      </Link>
                    );
                  })}
                </div>
              ) : null}
            </div>
          </nav>

          <div className="flex items-center gap-2">
            <GlobalSearch />
            <button 
              onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
              className="lg:hidden text-neutral-400 hover:text-white transition-colors p-2"
              aria-label="Toggle menu"
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <line x1="4" x2="20" y1="12" y2="12"/>
                <line x1="4" x2="20" y1="6" y2="6"/>
                <line x1="4" x2="20" y1="18" y2="18"/>
              </svg>
            </button>
          </div>
        </div>

        {/* Mobile Menu */}
        {mobileMenuOpen && (
          <nav className="lg:hidden border-t border-neutral-800 py-4">
            <div className="grid grid-cols-2 gap-1">
              {primaryLinks.map(link => {
                const isActive = link.href === '/' ? pathname === '/' : pathname.startsWith(link.href);
                return (
                  <Link
                    key={link.href}
                    href={link.href}
                    className={`flex items-center px-4 py-2.5 text-sm font-readex rounded-xl transition-colors hover:text-nor-green hover:bg-neutral-900/50 ${isActive ? 'text-nor-green bg-neutral-900/40' : 'text-neutral-300'}`}
                    onClick={() => setMobileMenuOpen(false)}
                  >
                    {link.label}
                  </Link>
                );
              })}
            </div>
            <div className="mt-2 pt-2 border-t border-neutral-800/50">
              <p className="px-4 pb-1.5 text-[10px] text-neutral-600 font-readex uppercase tracking-wide">المزيد</p>
              <div className="grid grid-cols-2 gap-1">
                {secondaryLinks.map(link => {
                  const isActive = pathname.startsWith(link.href);
                  return (
                    <Link
                      key={link.href}
                      href={link.href}
                      className={`flex items-center px-4 py-2.5 text-sm font-readex rounded-xl transition-colors hover:text-nor-green hover:bg-neutral-900/50 ${isActive ? 'text-nor-green bg-neutral-900/40' : 'text-neutral-400'}`}
                      onClick={() => setMobileMenuOpen(false)}
                    >
                      {link.label}
                    </Link>
                  );
                })}
              </div>
            </div>
          </nav>
        )}
      </div>
    </header>
  );
}
