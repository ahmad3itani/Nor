"use client";

import { useCallback, useEffect, useMemo, useState } from 'react';

export type FavoriteTeam = {
  id: string;
  name: string;
  logo: string;
  country?: string;
};

export type FavoriteLeague = {
  id: string;
  name: string;
  logo: string;
  country?: string;
};

type FavoritesState = {
  teams: FavoriteTeam[];
  leagues: FavoriteLeague[];
};

const STORAGE_KEY = 'nor:favorites';

function readFavorites(): FavoritesState {
  if (typeof window === 'undefined') {
    return { teams: [], leagues: [] };
  }

  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return { teams: [], leagues: [] };
    const parsed = JSON.parse(raw);
    return {
      teams: Array.isArray(parsed.teams) ? parsed.teams : [],
      leagues: Array.isArray(parsed.leagues) ? parsed.leagues : [],
    };
  } catch {
    return { teams: [], leagues: [] };
  }
}

function writeFavorites(value: FavoritesState) {
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(value));
}

export function useFavorites() {
  const [favorites, setFavorites] = useState<FavoritesState>({ teams: [], leagues: [] });
  const [ready, setReady] = useState(false);

  useEffect(() => {
    setFavorites(readFavorites());
    setReady(true);
  }, []);

  const toggleTeam = useCallback((team: FavoriteTeam) => {
    setFavorites((prev) => {
      const exists = prev.teams.some((item) => item.id === team.id);
      const next = {
        ...prev,
        teams: exists ? prev.teams.filter((item) => item.id !== team.id) : [team, ...prev.teams].slice(0, 12),
      };
      writeFavorites(next);
      return next;
    });
  }, []);

  const toggleLeague = useCallback((league: FavoriteLeague) => {
    setFavorites((prev) => {
      const exists = prev.leagues.some((item) => item.id === league.id);
      const next = {
        ...prev,
        leagues: exists ? prev.leagues.filter((item) => item.id !== league.id) : [league, ...prev.leagues].slice(0, 12),
      };
      writeFavorites(next);
      return next;
    });
  }, []);

  const isFavoriteTeam = useCallback((teamId: string) => favorites.teams.some((item) => item.id === teamId), [favorites.teams]);
  const isFavoriteLeague = useCallback((leagueId: string) => favorites.leagues.some((item) => item.id === leagueId), [favorites.leagues]);

  return useMemo(() => ({
    favorites,
    ready,
    toggleTeam,
    toggleLeague,
    isFavoriteTeam,
    isFavoriteLeague,
  }), [favorites, ready, toggleTeam, toggleLeague, isFavoriteTeam, isFavoriteLeague]);
}
