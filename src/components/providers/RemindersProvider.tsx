"use client";

import { useEffect } from 'react';
import { useReminders } from '@/hooks/useReminders';

export default function RemindersProvider() {
  const { reminders, ready, markNotified } = useReminders();

  useEffect(() => {
    if (!ready || typeof window === 'undefined' || !('Notification' in window)) {
      return;
    }

    const notifyDueMatches = () => {
      if (Notification.permission !== 'granted') return;

      const now = Date.now();

      reminders.forEach((reminder) => {
        if (reminder.notified) return;

        const kickoff = new Date(reminder.kickoffAt).getTime();
        const diff = kickoff - now;

        if (diff <= 15 * 60 * 1000 && diff >= -10 * 60 * 1000) {
          new Notification(`اقتربت مباراة ${reminder.matchLabel}`, {
            body: `${reminder.leagueName} تبدأ ${diff > 0 ? 'خلال دقائق' : 'الآن تقريباً'}.`,
            tag: `nor-reminder-${reminder.fixtureId}`,
          });
          markNotified(reminder.fixtureId);
        }
      });
    };

    notifyDueMatches();
    const interval = window.setInterval(notifyDueMatches, 60 * 1000);

    return () => window.clearInterval(interval);
  }, [ready, reminders, markNotified]);

  return null;
}
