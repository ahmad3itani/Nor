"use client";

import Link from 'next/link';
import { useFavorites } from '@/hooks/useFavorites';
import FavoriteButton from '@/components/ui/FavoriteButton';

export default function FavoritesPage() {
  const { favorites, ready } = useFavorites();

  if (!ready) {
    return <div className="bg-neutral-900 border border-neutral-800 rounded-2xl h-96 animate-pulse" />;
  }

  return (
    <div className="max-w-6xl mx-auto space-y-8">
      <div className="text-center">
        <h1 className="text-4xl font-bold font-readex mb-4 text-white">مفضلاتك</h1>
        <p className="text-neutral-400 font-ibm">احفظ الدوريات والفرق التي تهمك للوصول السريع إليها من أي مكان.</p>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6">
          <p className="text-sm text-neutral-500 font-readex">الدوريات المحفوظة</p>
          <p className="mt-2 text-4xl font-bold font-readex text-nor-green">{favorites.leagues.length}</p>
        </div>
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6">
          <p className="text-sm text-neutral-500 font-readex">الفرق المحفوظة</p>
          <p className="mt-2 text-4xl font-bold font-readex text-white">{favorites.teams.length}</p>
          {favorites.teams.length > 0 && (
            <Link href="/watchlist" className="mt-3 inline-block text-sm text-nor-green hover:underline font-readex">
              فتح قائمة المتابعة
            </Link>
          )}
        </div>
      </div>

      <div className="grid gap-8 lg:grid-cols-2">
        <section className="space-y-4">
          <h2 className="text-2xl font-bold font-readex border-r-4 border-nor-green pr-4">الدوريات</h2>
          {favorites.leagues.length > 0 ? (
            <div className="space-y-3">
              {favorites.leagues.map((league) => (
                <div key={league.id} className="flex items-center gap-3 rounded-2xl border border-neutral-800 bg-neutral-900 p-4">
                  <img src={league.logo} alt={league.name} className="w-12 h-12 object-contain" />
                  <div className="flex-1 min-w-0">
                    <p className="truncate font-readex font-bold text-white">{league.name}</p>
                    <p className="truncate text-xs text-neutral-500 font-ibm">{league.country || 'دوري'}</p>
                  </div>
                  <Link href={`/matches?league=${league.id}`} className="text-sm text-nor-green hover:underline font-readex">فتح</Link>
                  <FavoriteButton type="league" item={league} size="sm" />
                </div>
              ))}
            </div>
          ) : (
            <div className="rounded-2xl border border-neutral-800 bg-neutral-900 p-8 text-center text-neutral-500 font-ibm">
              لا توجد دوريات محفوظة بعد.
            </div>
          )}
        </section>

        <section className="space-y-4">
          <h2 className="text-2xl font-bold font-readex border-r-4 border-nor-green pr-4">الفرق</h2>
          {favorites.teams.length > 0 ? (
            <div className="space-y-3">
              {favorites.teams.map((team) => (
                <div key={team.id} className="flex items-center gap-3 rounded-2xl border border-neutral-800 bg-neutral-900 p-4">
                  <img src={team.logo} alt={team.name} className="w-12 h-12 object-contain" />
                  <div className="flex-1 min-w-0">
                    <p className="truncate font-readex font-bold text-white">{team.name}</p>
                    <p className="truncate text-xs text-neutral-500 font-ibm">{team.country || 'فريق'}</p>
                  </div>
                  <Link href={`/teams/${team.id}`} className="text-sm text-nor-green hover:underline font-readex">فتح</Link>
                  <FavoriteButton type="team" item={team} size="sm" />
                </div>
              ))}
            </div>
          ) : (
            <div className="rounded-2xl border border-neutral-800 bg-neutral-900 p-8 text-center text-neutral-500 font-ibm">
              لا توجد فرق محفوظة بعد.
            </div>
          )}
        </section>
      </div>
    </div>
  );
}
