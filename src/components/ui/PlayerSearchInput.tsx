"use client";

import { useEffect, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';

type PlayerOption = {
  id: number;
  name: string;
  photo: string;
  age?: number;
  nationality?: string;
  teamName?: string | null;
  teamLogo?: string | null;
};

type PlayerSearchInputProps = {
  label: string;
  value: string;
  selectedPlayer: PlayerOption | null;
  onQueryChange: (value: string) => void;
  onSelect: (player: PlayerOption) => void;
  excludePlayerId?: number | null;
};

export default function PlayerSearchInput({
  label,
  value,
  selectedPlayer,
  onQueryChange,
  onSelect,
  excludePlayerId,
}: PlayerSearchInputProps) {
  const [open, setOpen] = useState(false);
  const [debounced, setDebounced] = useState('');
  const containerRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // 450 ms debounce so we don't fire on every keystroke
  useEffect(() => {
    const t = setTimeout(() => setDebounced(value), 450);
    return () => clearTimeout(t);
  }, [value]);

  const { data, isFetching } = useQuery({
    queryKey: ['player-search', debounced],
    queryFn: async () => {
      const res = await fetch(`/api/search?q=${encodeURIComponent(debounced)}`);
      if (!res.ok) throw new Error('Failed to search players');
      return res.json();
    },
    enabled: debounced.trim().length >= 2 && !selectedPlayer,
    staleTime: 120000,
  });

  const options: PlayerOption[] = ((data?.players as PlayerOption[]) || []).filter(
    (p) => p.id !== excludePlayerId,
  );

  // Close dropdown on outside click
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  // Open dropdown whenever we have results or are searching
  useEffect(() => {
    if (debounced.trim().length >= 2 && !selectedPlayer) setOpen(true);
  }, [debounced, selectedPlayer]);

  const handleSelect = (player: PlayerOption) => {
    onSelect(player);   // parent sets both player + query — don't call onQueryChange or it resets player to null
    setOpen(false);
  };

  const handleClear = () => {
    onQueryChange('');
    setDebounced('');
    setOpen(false);
    setTimeout(() => inputRef.current?.focus(), 50);
  };

  return (
    <div className="space-y-2" ref={containerRef}>
      <label className="block text-sm font-readex font-bold text-neutral-300">{label}</label>

      {selectedPlayer ? (
        /* ── Selected state ────────────────────────────────────────── */
        <div className="flex items-center justify-between gap-3 rounded-2xl border border-nor-green/40 bg-nor-green/10 px-4 py-3">
          <div className="flex items-center gap-3 min-w-0">
            <img
              src={selectedPlayer.photo}
              alt={selectedPlayer.name}
              className="w-11 h-11 rounded-full object-cover border border-neutral-700 shrink-0"
            />
            <div className="min-w-0">
              <p className="truncate font-readex font-bold text-white text-sm">{selectedPlayer.name}</p>
              <p className="truncate text-xs text-neutral-400 font-ibm">
                {selectedPlayer.teamName || selectedPlayer.nationality || 'لاعب كرة قدم'}
              </p>
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
        /* ── Search combobox ────────────────────────────────────────── */
        <div className="relative">
          <div className="relative">
            <input
              ref={inputRef}
              type="text"
              value={value}
              onChange={(e) => {
                onQueryChange(e.target.value);
                if (e.target.value.trim().length >= 2) setOpen(true);
              }}
              onFocus={() => {
                if (value.trim().length >= 2) setOpen(true);
              }}
              placeholder="اكتب اسم اللاعب (2 حروف على الأقل)"
              className="w-full rounded-xl border border-neutral-700 bg-neutral-800 px-4 py-3 pe-10 text-white font-ibm text-sm placeholder-neutral-500 focus:outline-none focus:border-nor-green"
            />
            {/* Spinner or search icon */}
            <div className="absolute inset-y-0 left-3 flex items-center pointer-events-none">
              {isFetching ? (
                <svg className="w-4 h-4 text-nor-green animate-spin" viewBox="0 0 24 24" fill="none">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
                </svg>
              ) : (
                <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#525252" strokeWidth="2">
                  <circle cx="11" cy="11" r="8" /><path d="m21 21-4.35-4.35" />
                </svg>
              )}
            </div>
          </div>

          {/* Floating dropdown */}
          {open && value.trim().length >= 2 && (
            <div className="absolute top-full mt-1 inset-x-0 z-50 rounded-2xl border border-neutral-700 bg-neutral-900 shadow-2xl overflow-hidden">
              {isFetching ? (
                <div className="flex items-center gap-3 p-4 text-sm text-neutral-400 font-ibm">
                  <svg className="w-4 h-4 text-nor-green animate-spin shrink-0" viewBox="0 0 24 24" fill="none">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
                  </svg>
                  جاري البحث عن "{value}"...
                </div>
              ) : options.length > 0 ? (
                <div className="max-h-72 overflow-y-auto">
                  {options.map((player) => (
                    <button
                      key={player.id}
                      type="button"
                      onClick={() => handleSelect(player)}
                      className="flex w-full items-center gap-3 border-b border-neutral-800 px-4 py-3 text-right last:border-0 hover:bg-neutral-800/80 transition-colors"
                    >
                      <img
                        src={player.photo}
                        alt={player.name}
                        className="w-10 h-10 rounded-full object-cover border border-neutral-700 shrink-0"
                      />
                      <div className="min-w-0 flex-1">
                        <p className="truncate font-readex font-bold text-white text-sm">{player.name}</p>
                        <div className="flex items-center gap-1.5 mt-0.5">
                          {player.teamLogo && (
                            <img src={player.teamLogo} alt="" className="w-3.5 h-3.5 object-contain" />
                          )}
                          <p className="truncate text-xs text-neutral-500 font-ibm">
                            {player.teamName || player.nationality || 'لاعب'}
                            {player.age ? ` · ${player.age} عاماً` : ''}
                          </p>
                        </div>
                      </div>
                    </button>
                  ))}
                </div>
              ) : debounced.trim().length >= 2 ? (
                <div className="p-5 text-center space-y-1">
                  <p className="text-sm text-neutral-400 font-readex">لم يُعثر على لاعبين بهذا الاسم</p>
                  <p className="text-xs text-neutral-600 font-ibm">جرّب اسم آخر أو اكتب باللغة الإنجليزية</p>
                </div>
              ) : (
                <div className="p-4 text-sm text-neutral-500 font-ibm">واصل الكتابة للبحث...</div>
              )}
            </div>
          )}

          {value.trim().length < 2 && (
            <p className="mt-1.5 text-xs text-neutral-600 font-ibm px-1">
              مثال: Haaland, Messi, نيمار
            </p>
          )}
        </div>
      )}
    </div>
  );
}
