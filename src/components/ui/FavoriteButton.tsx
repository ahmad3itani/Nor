"use client";

import { useFavorites } from '@/hooks/useFavorites';

type FavoriteButtonProps =
  | {
      type: 'team';
      item: { id: string; name: string; logo: string; country?: string };
      size?: 'sm' | 'md';
    }
  | {
      type: 'league';
      item: { id: string; name: string; logo: string; country?: string };
      size?: 'sm' | 'md';
    };

export default function FavoriteButton({ type, item, size = 'md' }: FavoriteButtonProps) {
  const { ready, isFavoriteLeague, isFavoriteTeam, toggleLeague, toggleTeam } = useFavorites();
  const active = type === 'team' ? isFavoriteTeam(item.id) : isFavoriteLeague(item.id);

  const handleClick = () => {
    if (type === 'team') {
      toggleTeam(item);
      return;
    }
    toggleLeague(item);
  };

  const sizeClasses = size === 'sm' ? 'h-8 w-8' : 'h-10 w-10';

  return (
    <button
      type="button"
      onClick={handleClick}
      disabled={!ready}
      className={`${sizeClasses} inline-flex items-center justify-center rounded-full border transition-colors ${
        active
          ? 'border-nor-green bg-nor-green/15 text-nor-green'
          : 'border-neutral-700 bg-neutral-900/80 text-neutral-400 hover:border-neutral-500 hover:text-white'
      } disabled:opacity-60`}
      aria-label={active ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة'}
      title={active ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة'}
    >
      <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill={active ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="2">
        <path d="m12 17.27 6.18 3.73-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z"/>
      </svg>
    </button>
  );
}
