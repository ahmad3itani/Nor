"use client";
import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';

export default function AnalyticsCardsSection({ leagueId }: { leagueId: string }) {
  const { data: scorers } = useQuery({
    queryKey: ['scorers-cards', leagueId],
    queryFn: async () => {
      const res = await fetch(`/api/football/analytics/scorers?league=${leagueId}`);
      return res.ok ? res.json() : [];
    },
    staleTime: 3600000,
  });

  const { data: assists } = useQuery({
    queryKey: ['assists-cards', leagueId],
    queryFn: async () => {
      const res = await fetch(`/api/football/analytics/assists?league=${leagueId}`);
      return res.ok ? res.json() : [];
    },
    staleTime: 3600000,
  });

  const topScorer = scorers?.[0];
  const topAssist = assists?.[0];
  const totalGoals = scorers?.reduce((acc: number, p: any) => acc + (p.statistics?.[0]?.goals?.total || 0), 0) || 0;
  const totalAssists = assists?.reduce((acc: number, p: any) => acc + (p.statistics?.[0]?.goals?.assists || 0), 0) || 0;

  const cards = [
    {
      label: 'هداف الدوري',
      value: topScorer?.player?.name || '...',
      sub: `${topScorer?.statistics?.[0]?.goals?.total || 0} هدف`,
      photo: topScorer?.player?.photo,
      href: topScorer ? `/players/${topScorer.player.id}` : '#',
      color: 'border-nor-green/30 bg-nor-green/5',
    },
    {
      label: 'أفضل صانع أهداف',
      value: topAssist?.player?.name || '...',
      sub: `${topAssist?.statistics?.[0]?.goals?.assists || 0} تمريرة حاسمة`,
      photo: topAssist?.player?.photo,
      href: topAssist ? `/players/${topAssist.player.id}` : '#',
      color: 'border-blue-500/30 bg-blue-500/5',
    },
    {
      label: 'إجمالي أهداف أفضل 20',
      value: totalGoals.toString(),
      sub: 'أهداف مسجلة',
      color: 'border-yellow-500/30 bg-yellow-500/5',
    },
    {
      label: 'إجمالي تمريرات أفضل 20',
      value: totalAssists.toString(),
      sub: 'تمريرة حاسمة',
      color: 'border-purple-500/30 bg-purple-500/5',
    },
  ];

  return (
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
      {cards.map((card, i) => {
        const Wrapper = card.href ? Link : 'div';
        const wrapperProps = card.href ? { href: card.href } : {};
        return (
          <Wrapper key={i} {...(wrapperProps as any)} className={`border rounded-2xl p-5 transition-all hover:scale-[1.02] ${card.color}`}>
            <p className="text-xs text-neutral-500 font-readex mb-2">{card.label}</p>
            <div className="flex items-center gap-3">
              {card.photo && (
                <img src={card.photo} alt="" className="w-10 h-10 rounded-full object-cover border border-neutral-700" />
              )}
              <div>
                <p className="font-bold font-readex text-white text-lg leading-tight">{card.value}</p>
                <p className="text-xs text-neutral-400 font-ibm">{card.sub}</p>
              </div>
            </div>
          </Wrapper>
        );
      })}
    </div>
  );
}
