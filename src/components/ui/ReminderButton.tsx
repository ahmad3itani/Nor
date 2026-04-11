"use client";

import { useReminders } from '@/hooks/useReminders';

type ReminderButtonProps = {
  fixture: {
    fixture: { id: number; date: string };
    league: { name: string };
    teams: { home: { name: string }; away: { name: string } };
  };
};

export default function ReminderButton({ fixture }: ReminderButtonProps) {
  const { addReminder, removeReminder, isReminderSet } = useReminders();
  const isActive = isReminderSet(String(fixture.fixture.id));

  const handleClick = async () => {
    if (typeof window !== 'undefined' && 'Notification' in window && Notification.permission === 'default') {
      try {
        await Notification.requestPermission();
      } catch {}
    }

    if (isActive) {
      removeReminder(String(fixture.fixture.id));
      return;
    }

    addReminder({
      fixtureId: String(fixture.fixture.id),
      matchLabel: `${fixture.teams.home.name} ضد ${fixture.teams.away.name}`,
      kickoffAt: fixture.fixture.date,
      leagueName: fixture.league.name,
      teamNames: [fixture.teams.home.name, fixture.teams.away.name],
    });
  };

  return (
    <button
      type="button"
      onClick={handleClick}
      className={`px-3 py-1.5 rounded-full text-xs font-readex border transition-colors ${
        isActive
          ? 'border-yellow-500/30 bg-yellow-500/10 text-yellow-400'
          : 'border-neutral-700 bg-neutral-900 text-neutral-300 hover:border-nor-green hover:text-nor-green'
      }`}
    >
      {isActive ? 'تم التذكير' : 'ذكرني'}
    </button>
  );
}
