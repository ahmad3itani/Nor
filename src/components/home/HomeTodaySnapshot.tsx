"use client";

import Link from 'next/link';
import { useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useFavorites } from '@/hooks/useFavorites';
import { useReminders } from '@/hooks/useReminders';

const stats = [
  {
    href: '/live',
    label: 'مباشر',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="3"/></svg>
    ),
    accent: 'text-red-400',
    border: 'border-red-500/20',
    dot: 'bg-red-500',
  },
  {
    href: '/watchlist',
    label: 'المتابعة',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/></svg>
    ),
    accent: 'text-blue-400',
    border: 'border-blue-500/20',
    dot: null,
  },
  {
    href: '/favorites',
    label: 'المفضلة',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/></svg>
    ),
    accent: 'text-amber-300',
    border: 'border-amber-400/20',
    dot: null,
  },
  {
    href: '/reminders',
    label: 'التنبيهات',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/></svg>
    ),
    accent: 'text-nor-green',
    border: 'border-nor-green/20',
    dot: null,
  },
];

export default function HomeTodaySnapshot() {
  const { favorites, ready: favoritesReady } = useFavorites();
  const { upcomingReminders, ready: remindersReady } = useReminders();

  const liveMatchesQuery = useQuery({
    queryKey: ['live-matches'],
    queryFn: async () => {
      const res = await fetch('/api/football/live');
      if (!res.ok) throw new Error('Failed to fetch live matches');
      return res.json();
    },
    staleTime: 15000,
    refetchInterval: 30000,
  });

  const teamIds = useMemo(() => favorites.teams.map((team) => team.id).join(','), [favorites.teams]);
  const watchlistQuery = useQuery({
    queryKey: ['home-watchlist-snapshot', teamIds],
    queryFn: async () => {
      const res = await fetch(`/api/football/watchlist?teamIds=${teamIds}`);
      if (!res.ok) throw new Error('Failed to fetch watchlist snapshot');
      return res.json();
    },
    enabled: favoritesReady && favorites.teams.length > 0,
    staleTime: 300000,
  });

  const liveCount = Array.isArray(liveMatchesQuery.data) ? liveMatchesQuery.data.length : 0;
  const watchlistCount = Array.isArray(watchlistQuery.data)
    ? watchlistQuery.data.reduce((sum: number, entry: any) => sum + (entry.fixtures?.length || 0), 0)
    : 0;

  const values = [
    liveMatchesQuery.isLoading ? '...' : String(liveCount),
    !favoritesReady ? '...' : String(watchlistCount),
    !favoritesReady ? '...' : String(favorites.teams.length + favorites.leagues.length),
    !remindersReady ? '...' : String(upcomingReminders.length),
  ];

  return (
    <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
      {stats.map((s, i) => (
        <Link
          key={s.href}
          href={s.href}
          className={`flex items-center gap-3 bg-neutral-900 border ${s.border} rounded-2xl px-4 py-3.5 hover:bg-neutral-800/80 transition-all group`}
        >
          <div className={`shrink-0 ${s.accent}`}>{s.icon}</div>
          <div className="min-w-0">
            <div className="flex items-center gap-1.5">
              <span className="text-2xl font-black font-readex text-white leading-none">{values[i]}</span>
              {s.dot && values[i] !== '0' && values[i] !== '...' && (
                <span className={`w-1.5 h-1.5 rounded-full ${s.dot} animate-pulse shrink-0`} />
              )}
            </div>
            <p className={`text-xs font-readex mt-0.5 ${s.accent}`}>{s.label}</p>
          </div>
        </Link>
      ))}
    </div>
  );
}
