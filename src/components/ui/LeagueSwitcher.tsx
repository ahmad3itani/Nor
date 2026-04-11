"use client";
import { useRouter, useSearchParams, usePathname } from 'next/navigation';
import { useState } from 'react';
import { LEAGUE_CATEGORIES, SUPPORTED_LEAGUES } from '@/lib/config/leagues';
import FavoriteButton from './FavoriteButton';

type LeagueSwitcherProps = {
  allowAll?: boolean;
  defaultLeague?: string;
  allLabel?: string;
};

export default function LeagueSwitcher({
  allowAll = false,
  defaultLeague = '39',
  allLabel = 'كل الدوريات',
}: LeagueSwitcherProps) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [expanded, setExpanded] = useState(false);
  
  const currentLeague = searchParams.get('league') || defaultLeague;

  const handleSelect = (id: string) => {
    const params = new URLSearchParams(searchParams.toString());
    params.set('league', id);
    router.push(`${pathname}?${params.toString()}`);
    setExpanded(false);
  };

  const currentLeagueData = SUPPORTED_LEAGUES.find(l => l.id === currentLeague);

  return (
    <div className="w-full mb-8">
      {/* Compact bar with current league + expand button */}
      <div className="flex items-center gap-3 pb-3 border-b border-neutral-800">
        <div className="flex items-center gap-2 overflow-x-auto hide-scrollbar flex-1">
          {allowAll && (
            <button
              onClick={() => handleSelect('all')}
              className={`flex items-center gap-2 px-4 py-2 rounded-full font-readex text-sm transition-all duration-300 shrink-0 ${
                currentLeague === 'all'
                  ? 'bg-nor-green text-[#080808] font-bold shadow-[0_0_15px_rgba(0,255,133,0.3)]'
                  : 'bg-neutral-900 border border-neutral-800 text-neutral-400 hover:text-white hover:border-neutral-600'
              }`}
            >
              <span className="whitespace-nowrap">{allLabel}</span>
            </button>
          )}
          {LEAGUE_CATEGORIES[0].leagues.map((league) => {
            const isActive = currentLeague === league.id;
            return (
              <button
                key={league.id}
                onClick={() => handleSelect(league.id)}
                className={`flex items-center gap-2 px-4 py-2 rounded-full font-readex text-sm transition-all duration-300 shrink-0 ${
                  isActive 
                    ? 'bg-nor-green text-[#080808] font-bold shadow-[0_0_15px_rgba(0,255,133,0.3)]' 
                    : 'bg-neutral-900 border border-neutral-800 text-neutral-400 hover:text-white hover:border-neutral-600'
                }`}
              >
                <img src={league.logo} alt={league.name} className={`w-5 h-5 object-contain ${isActive ? 'filter brightness-0' : ''}`} />
                <span className="whitespace-nowrap">{league.name}</span>
              </button>
            );
          })}
        </div>
        {currentLeagueData && currentLeague !== 'all' && (
          <FavoriteButton
            type="league"
            item={{
              id: currentLeagueData.id,
              name: currentLeagueData.name,
              logo: currentLeagueData.logo,
              country: currentLeagueData.country,
            }}
            size="sm"
          />
        )}
        <button
          onClick={() => setExpanded(!expanded)}
          className={`shrink-0 flex items-center gap-2 px-4 py-2 rounded-full font-readex text-sm border transition-all ${
            expanded ? 'bg-nor-green/10 border-nor-green text-nor-green' : 'bg-neutral-900 border-neutral-800 text-neutral-400 hover:text-white'
          }`}
        >
          <span>كل الدوريات</span>
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className={`transition-transform ${expanded ? 'rotate-180' : ''}`}><path d="m6 9 6 6 6-6"/></svg>
        </button>
      </div>

      {/* Expanded panel */}
        {expanded && (
        <div className="mt-4 bg-neutral-900 border border-neutral-800 rounded-2xl p-6 animate-slide-in-right">
          {allowAll && (
            <div className="mb-5">
              <button
                onClick={() => handleSelect('all')}
                className={`flex items-center gap-2 px-3 py-2 rounded-lg font-readex text-xs transition-all ${
                  currentLeague === 'all'
                    ? 'bg-nor-green text-[#080808] font-bold'
                    : 'bg-neutral-800/50 border border-neutral-700/50 text-neutral-300 hover:text-white'
                }`}
              >
                <span className="whitespace-nowrap">{allLabel}</span>
              </button>
            </div>
          )}
          {LEAGUE_CATEGORIES.map((cat) => (
            <div key={cat.label} className="mb-5 last:mb-0">
              <h4 className="text-xs font-readex text-neutral-500 uppercase tracking-wider mb-3">{cat.label}</h4>
              <div className="flex flex-wrap gap-2">
                {cat.leagues.map((league) => {
                  const isActive = currentLeague === league.id;
                  return (
                    <div
                      key={league.id}
                      className={`flex items-center gap-2 px-2 py-1 rounded-lg ${
                        isActive ? 'bg-nor-green text-[#080808]' : 'bg-neutral-800/50 border border-neutral-700/50'
                      }`}
                    >
                      <button
                        onClick={() => handleSelect(league.id)}
                        className={`flex items-center gap-2 px-1 py-0.5 rounded-lg font-readex text-xs transition-all ${
                          isActive 
                            ? 'text-[#080808] font-bold' 
                            : 'text-neutral-300 hover:text-white'
                        }`}
                      >
                        <img src={league.logo} alt={league.name} className={`w-4 h-4 object-contain ${isActive ? 'filter brightness-0' : ''}`} />
                        <span className="whitespace-nowrap">{league.name}</span>
                      </button>
                      <FavoriteButton
                        type="league"
                        item={{ id: league.id, name: league.name, logo: league.logo, country: league.country }}
                        size="sm"
                      />
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
