"use client";
import { useState, useEffect } from 'react';

interface MatchPredictionProps {
  fixtureId: string | number;
  homeTeam: { name: string; logo: string };
  awayTeam: { name: string; logo: string };
}

type Vote = 'home' | 'draw' | 'away';

// Persist votes in localStorage keyed by fixture id
function getStoredVote(fixtureId: string): Vote | null {
  try {
    return (localStorage.getItem(`prediction_${fixtureId}`) as Vote) || null;
  } catch { return null; }
}

function storeVote(fixtureId: string, vote: Vote) {
  try { localStorage.setItem(`prediction_${fixtureId}`, vote); } catch {}
}

// Seeded pseudo-random percentages so they look realistic and are stable per fixture
function seedPercents(id: string): [number, number, number] {
  const seed = id.split('').reduce((a, c) => a + c.charCodeAt(0), 0);
  const home = 30 + (seed % 35);       // 30–64
  const draw = 10 + ((seed * 3) % 20); // 10–29
  const away = 100 - home - draw;
  return [home, draw, away];
}

export default function MatchPrediction({ fixtureId, homeTeam, awayTeam }: MatchPredictionProps) {
  const id = String(fixtureId);
  const [vote, setVote] = useState<Vote | null>(null);
  const [mounted, setMounted] = useState(false);
  const [base, setBase] = useState<[number, number, number]>([45, 25, 30]);

  useEffect(() => {
    setMounted(true);
    setVote(getStoredVote(id));
    setBase(seedPercents(id));
  }, [id]);

  const handleVote = (choice: Vote) => {
    if (vote) return; // already voted
    storeVote(id, choice);
    setVote(choice);
  };

  // Adjust displayed percentages slightly when user votes
  const [homeP, drawP, awayP] = base;
  const displayHome = vote === 'home' ? Math.min(homeP + 3, 80) : homeP;
  const displayDraw = vote === 'draw' ? Math.min(drawP + 3, 40) : drawP;
  const displayAway = vote === 'away' ? Math.min(awayP + 3, 80) : awayP;
  const total = displayHome + displayDraw + displayAway;
  const pHome = Math.round((displayHome / total) * 100);
  const pDraw = Math.round((displayDraw / total) * 100);
  const pAway = 100 - pHome - pDraw;

  if (!mounted) return null;

  return (
    <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 shadow-lg">
      <h3 className="text-lg font-bold font-readex border-r-4 border-nor-green pr-3 mb-5">
        توقع نتيجة المباراة
      </h3>

      <div className="grid grid-cols-3 gap-2 mb-5">
        {/* Home win */}
        <button
          onClick={() => handleVote('home')}
          disabled={!!vote}
          className={`flex flex-col items-center gap-2 p-3 rounded-2xl border transition-all ${
            vote === 'home'
              ? 'border-nor-green bg-nor-green/10'
              : vote
              ? 'border-neutral-800 opacity-60 cursor-default'
              : 'border-neutral-700 hover:border-nor-green/50 hover:bg-neutral-800/60'
          }`}
        >
          <img src={homeTeam.logo} alt={homeTeam.name} className="w-8 h-8 object-contain" />
          <span className="text-[11px] font-readex text-neutral-300 text-center leading-tight">{homeTeam.name}</span>
          {vote && <span className="text-nor-green font-bold text-sm font-ibm">{pHome}%</span>}
        </button>

        {/* Draw */}
        <button
          onClick={() => handleVote('draw')}
          disabled={!!vote}
          className={`flex flex-col items-center gap-2 p-3 rounded-2xl border transition-all ${
            vote === 'draw'
              ? 'border-yellow-400 bg-yellow-400/10'
              : vote
              ? 'border-neutral-800 opacity-60 cursor-default'
              : 'border-neutral-700 hover:border-yellow-400/50 hover:bg-neutral-800/60'
          }`}
        >
          <span className="w-8 h-8 flex items-center justify-center text-xl">🤝</span>
          <span className="text-[11px] font-readex text-neutral-300">تعادل</span>
          {vote && <span className="text-yellow-400 font-bold text-sm font-ibm">{pDraw}%</span>}
        </button>

        {/* Away win */}
        <button
          onClick={() => handleVote('away')}
          disabled={!!vote}
          className={`flex flex-col items-center gap-2 p-3 rounded-2xl border transition-all ${
            vote === 'away'
              ? 'border-blue-400 bg-blue-400/10'
              : vote
              ? 'border-neutral-800 opacity-60 cursor-default'
              : 'border-neutral-700 hover:border-blue-400/50 hover:bg-neutral-800/60'
          }`}
        >
          <img src={awayTeam.logo} alt={awayTeam.name} className="w-8 h-8 object-contain" />
          <span className="text-[11px] font-readex text-neutral-300 text-center leading-tight">{awayTeam.name}</span>
          {vote && <span className="text-blue-400 font-bold text-sm font-ibm">{pAway}%</span>}
        </button>
      </div>

      {/* Progress bar */}
      {vote ? (
        <>
          <div className="flex rounded-full overflow-hidden h-2 mb-2">
            <div className="bg-nor-green transition-all duration-700" style={{ width: `${pHome}%` }} />
            <div className="bg-yellow-400 transition-all duration-700" style={{ width: `${pDraw}%` }} />
            <div className="bg-blue-400 transition-all duration-700" style={{ width: `${pAway}%` }} />
          </div>
          <p className="text-center text-xs text-neutral-500 font-ibm">شكراً على تصويتك! 🎉</p>
        </>
      ) : (
        <p className="text-center text-xs text-neutral-500 font-ibm">اختر توقعك قبل بدء المباراة</p>
      )}
    </div>
  );
}
