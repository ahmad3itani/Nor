"use client";

import Link from 'next/link';
import { useFavorites } from '@/hooks/useFavorites';

export default function HomeFavoritesSection() {
  const { favorites, ready } = useFavorites();

  if (!ready || (!favorites.teams.length && !favorites.leagues.length)) {
    return null;
  }

  return (
    <section className="space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-bold font-readex border-r-4 border-amber-400 pr-3 text-white">
          متابعاتي
        </h2>
        <Link href="/favorites" className="text-sm text-nor-green font-readex hover:underline">
          إدارة المفضلة ←
        </Link>
      </div>

      <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-5 space-y-5">
        {favorites.leagues.length > 0 && (
          <div className="space-y-3">
            <p className="text-xs font-readex text-neutral-500 uppercase tracking-wide">الدوريات</p>
            <div className="flex flex-wrap gap-2">
              {favorites.leagues.slice(0, 8).map((league) => (
                <Link
                  key={league.id}
                  href={`/matches?league=${league.id}`}
                  className="flex items-center gap-2 rounded-full border border-neutral-700 bg-neutral-800 px-3 py-1.5 hover:border-nor-green/50 hover:bg-neutral-700 transition-all"
                >
                  <img src={league.logo} alt={league.name} className="w-5 h-5 object-contain" />
                  <span className="text-xs font-readex text-white">{league.name}</span>
                </Link>
              ))}
            </div>
          </div>
        )}

        {favorites.teams.length > 0 && (
          <div className="space-y-3">
            <p className="text-xs font-readex text-neutral-500 uppercase tracking-wide">الفرق</p>
            <div className="flex flex-wrap gap-2">
              {favorites.teams.slice(0, 10).map((team) => (
                <Link
                  key={team.id}
                  href={`/teams/${team.id}`}
                  className="flex items-center gap-2 rounded-full border border-neutral-700 bg-neutral-800 px-3 py-1.5 hover:border-nor-green/50 hover:bg-neutral-700 transition-all"
                >
                  <img src={team.logo} alt={team.name} className="w-5 h-5 object-contain" />
                  <span className="text-xs font-readex text-white">{team.name}</span>
                </Link>
              ))}
            </div>
          </div>
        )}
      </div>
    </section>
  );
}
