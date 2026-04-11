"use client";

import { useMemo } from 'react';
import { useReminders } from '@/hooks/useReminders';

export default function RemindersPage() {
  const { ready, upcomingReminders, removeReminder } = useReminders();
  const notificationState = useMemo(() => {
    if (typeof window === 'undefined' || !('Notification' in window)) return 'unsupported';
    return Notification.permission;
  }, []);

  const requestPermission = async () => {
    if (typeof window === 'undefined' || !('Notification' in window)) return;
    try {
      await Notification.requestPermission();
    } catch {}
  };

  if (!ready) {
    return <div className="bg-neutral-900 border border-neutral-800 rounded-2xl h-96 animate-pulse" />;
  }

  return (
    <div className="max-w-5xl mx-auto space-y-8">
      <div className="text-center space-y-4">
        <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-yellow-500/10 border border-yellow-500/20 rounded-full text-yellow-400 text-sm font-readex">
          <span className="w-2 h-2 rounded-full bg-yellow-400"></span>
          التنبيهات
        </div>
        <h1 className="text-4xl sm:text-5xl font-bold font-readex text-white">تذكيرات المباريات</h1>
        <p className="text-neutral-400 font-ibm text-lg max-w-3xl mx-auto">
          فعّل تنبيهات المتصفح واحتفظ بقائمة المباريات التي تريد تذكيراً قبل بدايتها.
        </p>
      </div>

      <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-6 flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
        <div>
          <p className="text-sm text-neutral-500 font-readex">حالة التنبيهات</p>
          <p className="mt-2 text-lg font-readex text-white">
            {notificationState === 'granted' && 'مفعلة'}
            {notificationState === 'denied' && 'مرفوضة من المتصفح'}
            {notificationState === 'default' && 'غير مفعلة بعد'}
            {notificationState === 'unsupported' && 'غير مدعومة في هذا المتصفح'}
          </p>
        </div>
        {notificationState !== 'granted' && notificationState !== 'unsupported' && (
          <button
            onClick={requestPermission}
            className="px-4 py-2 rounded-full border border-neutral-700 text-sm font-readex hover:border-nor-green hover:text-nor-green transition-colors"
          >
            تفعيل تنبيهات المتصفح
          </button>
        )}
      </div>

      {upcomingReminders.length > 0 ? (
        <div className="space-y-3">
          {upcomingReminders.map((reminder) => (
            <div key={reminder.fixtureId} className="bg-neutral-900 border border-neutral-800 rounded-2xl p-5 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
              <div>
                <p className="text-lg font-readex font-bold text-white">{reminder.matchLabel}</p>
                <p className="text-sm text-neutral-500 font-ibm">
                  {reminder.leagueName} • {new Date(reminder.kickoffAt).toLocaleDateString('ar-EG', { weekday: 'long', month: 'long', day: 'numeric' })} •{' '}
                  {new Date(reminder.kickoffAt).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })}
                </p>
              </div>
              <button
                onClick={() => removeReminder(reminder.fixtureId)}
                className="px-4 py-2 rounded-full border border-neutral-700 text-sm font-readex text-neutral-300 hover:border-red-500/40 hover:text-red-400 transition-colors"
              >
                إزالة التذكير
              </button>
            </div>
          ))}
        </div>
      ) : (
        <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-12 text-center">
          <p className="text-neutral-300 font-readex text-lg">لا توجد تذكيرات محفوظة بعد</p>
          <p className="mt-2 text-sm text-neutral-500 font-ibm">أضف تذكيراً من صفحة المتابعة أو من المباريات القادمة لاحقاً.</p>
        </div>
      )}
    </div>
  );
}
