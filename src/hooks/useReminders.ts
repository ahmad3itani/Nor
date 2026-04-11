"use client";

import { useCallback, useEffect, useMemo, useState } from 'react';

export type MatchReminder = {
  fixtureId: string;
  matchLabel: string;
  kickoffAt: string;
  leagueName: string;
  teamNames: [string, string];
  notified: boolean;
  createdAt: string;
};

const STORAGE_KEY = 'nor:reminders';

function readReminders(): MatchReminder[] {
  if (typeof window === 'undefined') return [];

  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function writeReminders(reminders: MatchReminder[]) {
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(reminders));
}

export function useReminders() {
  const [reminders, setReminders] = useState<MatchReminder[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    setReminders(readReminders());
    setReady(true);
  }, []);

  const addReminder = useCallback((reminder: Omit<MatchReminder, 'notified' | 'createdAt'>) => {
    setReminders((prev) => {
      if (prev.some((item) => item.fixtureId === reminder.fixtureId)) {
        return prev;
      }

      const next = [
        {
          ...reminder,
          notified: false,
          createdAt: new Date().toISOString(),
        },
        ...prev,
      ].sort((a, b) => new Date(a.kickoffAt).getTime() - new Date(b.kickoffAt).getTime());

      writeReminders(next);
      return next;
    });
  }, []);

  const removeReminder = useCallback((fixtureId: string) => {
    setReminders((prev) => {
      const next = prev.filter((item) => item.fixtureId !== fixtureId);
      writeReminders(next);
      return next;
    });
  }, []);

  const markNotified = useCallback((fixtureId: string) => {
    setReminders((prev) => {
      const next = prev.map((item) => item.fixtureId === fixtureId ? { ...item, notified: true } : item);
      writeReminders(next);
      return next;
    });
  }, []);

  const isReminderSet = useCallback((fixtureId: string) => reminders.some((item) => item.fixtureId === fixtureId), [reminders]);

  const upcomingReminders = useMemo(() => {
    const now = Date.now();
    return reminders
      .filter((item) => new Date(item.kickoffAt).getTime() >= now - 1000 * 60 * 60)
      .sort((a, b) => new Date(a.kickoffAt).getTime() - new Date(b.kickoffAt).getTime());
  }, [reminders]);

  return {
    reminders,
    upcomingReminders,
    ready,
    addReminder,
    removeReminder,
    markNotified,
    isReminderSet,
  };
}
