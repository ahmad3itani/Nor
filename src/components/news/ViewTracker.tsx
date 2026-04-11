'use client';
import { useEffect } from 'react';

export default function ViewTracker({ slug }: { slug: string }) {
  useEffect(() => {
    // Fire once per session per article
    const key = `viewed_${slug}`;
    if (sessionStorage.getItem(key)) return;
    sessionStorage.setItem(key, '1');
    fetch(`/api/news/${slug}/view`, { method: 'POST' }).catch(() => {});
  }, [slug]);

  return null;
}
