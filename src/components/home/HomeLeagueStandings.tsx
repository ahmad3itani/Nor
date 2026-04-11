"use client";
import { useState } from 'react';
import MiniStandingsWidget from '@/components/matches/MiniStandingsWidget';
import { TOP_5_LEAGUES, ARAB_LEAGUES } from '@/lib/config/leagues';

const tabs = [...TOP_5_LEAGUES.slice(0, 4), ARAB_LEAGUES[0]];

export default function HomeLeagueStandings() {
  const [activeTab, setActiveTab] = useState(tabs[0].id);

  return (
    <div className="bg-neutral-900 rounded-2xl p-5 border border-neutral-800">
      <h3 className="font-readex font-bold text-lg mb-4 flex items-center gap-2">
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-nor-green"><path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>
        ترتيب الدوريات
      </h3>

      {/* League Tabs */}
      <div className="flex gap-1 overflow-x-auto hide-scrollbar mb-1 border-b border-neutral-800 pb-2">
        {tabs.map((league) => (
          <button
            key={league.id}
            onClick={() => setActiveTab(league.id)}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg font-readex text-xs transition-all shrink-0 ${
              activeTab === league.id
                ? 'bg-nor-green/10 text-nor-green border border-nor-green/30'
                : 'text-neutral-500 hover:text-white'
            }`}
          >
            <img src={league.logo} alt="" className="w-4 h-4 object-contain" />
            <span className="whitespace-nowrap">{league.name.replace('الدوري ', '')}</span>
          </button>
        ))}
      </div>

      {/* Standings Content */}
      <MiniStandingsWidget leagueId={activeTab} />
    </div>
  );
}
