"use client";

import TeamSearchInput from '@/components/ui/TeamSearchInput';
import { SUPPORTED_LEAGUES, getLeagueMap } from '@/lib/config/leagues';

type TeamOption = {
  id: number;
  name: string;
  logo: string;
  country: string;
  founded?: number | null;
  venueName?: string | null;
};

type TeamPairSelectorProps = {
  leagueId: string;
  onLeagueChange: (leagueId: string) => void;
  team1: TeamOption | null;
  team2: TeamOption | null;
  team1Query: string;
  team2Query: string;
  onTeam1QueryChange: (value: string) => void;
  onTeam2QueryChange: (value: string) => void;
  onTeam1Select: (team: TeamOption) => void;
  onTeam2Select: (team: TeamOption) => void;
  title?: string;
  description?: string;
};

export default function TeamPairSelector({
  leagueId,
  onLeagueChange,
  team1,
  team2,
  team1Query,
  team2Query,
  onTeam1QueryChange,
  onTeam2QueryChange,
  onTeam1Select,
  onTeam2Select,
  title = 'اختيار الفريقين',
  description = 'اختر البطولة ثم حدّد الفريقين من نفس الدوري.',
}: TeamPairSelectorProps) {
  const leagueData = getLeagueMap(leagueId);

  return (
    <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 space-y-6">
      <div className="space-y-2">
        <h2 className="text-2xl font-bold font-readex text-white">{title}</h2>
        <p className="text-sm text-neutral-500 font-ibm">{description}</p>
      </div>

      <div className="space-y-3">
        <label className="block text-sm font-readex font-bold text-neutral-300">الدوري</label>
        <div className="flex gap-2 overflow-x-auto pb-2 hide-scrollbar">
          {SUPPORTED_LEAGUES.slice(0, 10).map((league) => {
            const active = league.id === leagueId;
            return (
              <button
                key={league.id}
                type="button"
                onClick={() => onLeagueChange(league.id)}
                className={`flex items-center gap-2 rounded-full border px-4 py-2 text-sm font-readex transition-colors shrink-0 ${
                  active
                    ? 'border-nor-green bg-nor-green text-black font-bold'
                    : 'border-neutral-700 bg-neutral-800 text-neutral-300 hover:border-neutral-500 hover:text-white'
                }`}
              >
                <img src={league.logo} alt={league.name} className={`h-5 w-5 object-contain ${active ? 'brightness-0' : ''}`} />
                <span>{league.name}</span>
              </button>
            );
          })}
        </div>
        <p className="text-xs text-neutral-500 font-ibm">
          الاختيار الحالي داخل {leagueData.name}. ستتم مطابقة الفرق والإحصائيات ضمن نفس البطولة.
        </p>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <TeamSearchInput
          label="الفريق الأول"
          leagueId={leagueId}
          value={team1 ? team1.name : team1Query}
          selectedTeam={team1}
          onQueryChange={onTeam1QueryChange}
          onSelect={onTeam1Select}
          excludeTeamId={team2?.id || null}
        />

        <TeamSearchInput
          label="الفريق الثاني"
          leagueId={leagueId}
          value={team2 ? team2.name : team2Query}
          selectedTeam={team2}
          onQueryChange={onTeam2QueryChange}
          onSelect={onTeam2Select}
          excludeTeamId={team1?.id || null}
        />
      </div>
    </div>
  );
}
