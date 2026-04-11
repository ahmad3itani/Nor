"use client";

import { useEffect, useMemo, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';

type TeamOption = {
  id: number;
  name: string;
  logo: string;
  country: string;
  founded?: number | null;
  venueName?: string | null;
};

type TeamSearchInputProps = {
  label: string;
  leagueId: string;
  value: string;
  selectedTeam: TeamOption | null;
  onQueryChange: (value: string) => void;
  onSelect: (team: TeamOption) => void;
  excludeTeamId?: number | null;
};

export default function TeamSearchInput({
  label,
  leagueId,
  selectedTeam,
  onQueryChange,
  onSelect,
  excludeTeamId,
}: TeamSearchInputProps) {
  const [filter, setFilter] = useState('');
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  // Pre-load all teams in the league from standings — no spelling required
  const { data: standingsData, isLoading } = useQuery({
    queryKey: ['team-selector-standings', leagueId],
    queryFn: async () => {
      const res = await fetch(`/api/football/standings?league=${leagueId}`);
      if (!res.ok) throw new Error('Failed to fetch standings');
      return res.json();
    },
    staleTime: 3600000,
    enabled: !!leagueId,
  });

  const allTeams: TeamOption[] = useMemo(() => {
    const raw: any[] = standingsData?.[0]?.league?.standings?.[0] || [];
    return raw
      .map((entry: any) => ({
        id: entry.team.id,
        name: entry.team.name,
        logo: entry.team.logo,
        country: entry.team.country || '',
        founded: null,
        venueName: null,
      }))
      .filter((t: TeamOption) => t.id !== excludeTeamId);
  }, [standingsData, excludeTeamId]);

  const filtered = useMemo(() => {
    if (!filter.trim()) return allTeams;
    const q = filter.toLowerCase();
    return allTeams.filter((t) => t.name.toLowerCase().includes(q));
  }, [allTeams, filter]);

  // Close on outside click
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  // Reset filter when league changes
  useEffect(() => {
    setFilter('');
    setOpen(false);
  }, [leagueId]);

  const handleSelect = (team: TeamOption) => {
    onSelect(team);   // parent sets both team + query — don't call onQueryChange or it resets team to null
    setFilter('');
    setOpen(false);
  };

  const handleClear = () => {
    onQueryChange('');
    setFilter('');
    setOpen(false);
  };

  return (
    <div className="space-y-2" ref={containerRef}>
      <label className="block text-sm font-readex font-bold text-neutral-300">{label}</label>

      {selectedTeam ? (
        /* ── Selected state ─────────────────────────────────────────── */
        <div className="flex items-center justify-between gap-3 rounded-2xl border border-nor-green/40 bg-nor-green/10 px-4 py-3">
          <div className="flex items-center gap-3 min-w-0">
            <img src={selectedTeam.logo} alt={selectedTeam.name} className="w-9 h-9 object-contain shrink-0" />
            <div className="min-w-0">
              <p className="truncate font-readex font-bold text-white text-sm">{selectedTeam.name}</p>
              <p className="truncate text-xs text-neutral-400 font-ibm">{selectedTeam.country}</p>
            </div>
          </div>
          <button
            type="button"
            onClick={handleClear}
            className="shrink-0 rounded-full border border-neutral-700 bg-neutral-900 px-3 py-1.5 text-xs font-readex text-neutral-300 hover:border-neutral-500 hover:text-white transition-colors"
          >
            تغيير
          </button>
        </div>
      ) : (
        /* ── Dropdown combobox ──────────────────────────────────────── */
        <div className="relative">
          <button
            type="button"
            onClick={() => setOpen((v) => !v)}
            className={`w-full flex items-center justify-between gap-2 rounded-xl border px-4 py-3 text-right transition-colors ${
              open ? 'border-nor-green bg-neutral-800' : 'border-neutral-700 bg-neutral-800 hover:border-neutral-600'
            }`}
          >
            <span className={`font-ibm text-sm truncate ${isLoading ? 'text-neutral-500' : 'text-neutral-300'}`}>
              {isLoading ? 'جاري تحميل الفرق...' : allTeams.length > 0 ? 'اختر فريقاً...' : 'لا توجد فرق متاحة'}
            </span>
            <svg
              xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24"
              fill="none" stroke="currentColor" strokeWidth="2"
              className={`shrink-0 text-neutral-400 transition-transform ${open ? 'rotate-180' : ''}`}
            >
              <path d="m6 9 6 6 6-6" />
            </svg>
          </button>

          {open && (
            <div className="absolute top-full mt-1 inset-x-0 z-50 rounded-2xl border border-neutral-700 bg-neutral-900 shadow-2xl overflow-hidden">
              {/* Search filter inside dropdown */}
              <div className="p-2 border-b border-neutral-800">
                <input
                  autoFocus
                  type="text"
                  value={filter}
                  onChange={(e) => setFilter(e.target.value)}
                  placeholder="ابحث في القائمة..."
                  className="w-full rounded-xl border border-neutral-700 bg-neutral-800 px-3 py-2 text-sm text-white font-ibm placeholder-neutral-500 focus:outline-none focus:border-nor-green"
                />
              </div>

              <div className="max-h-64 overflow-y-auto">
                {isLoading ? (
                  <div className="p-4 text-sm text-neutral-500 font-ibm text-center">جاري تحميل الفرق...</div>
                ) : filtered.length > 0 ? (
                  filtered.map((team) => (
                    <button
                      key={team.id}
                      type="button"
                      onClick={() => handleSelect(team)}
                      className="flex w-full items-center gap-3 border-b border-neutral-800 px-4 py-3 text-right last:border-0 hover:bg-neutral-800/80 transition-colors"
                    >
                      <img src={team.logo} alt={team.name} className="w-8 h-8 object-contain shrink-0" />
                      <div className="min-w-0 flex-1">
                        <p className="truncate font-readex font-bold text-white text-sm">{team.name}</p>
                        <p className="truncate text-xs text-neutral-500 font-ibm">{team.country}</p>
                      </div>
                    </button>
                  ))
                ) : (
                  <div className="p-4 text-sm text-neutral-500 font-ibm text-center">لا توجد نتائج مطابقة</div>
                )}
              </div>

              {allTeams.length > 0 && (
                <div className="px-4 py-2 border-t border-neutral-800 bg-neutral-950/60">
                  <p className="text-[11px] text-neutral-600 font-ibm">{allTeams.length} فريق في هذه البطولة</p>
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
