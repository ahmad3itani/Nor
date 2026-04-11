import { format } from 'date-fns';
import Link from 'next/link';
import { isFinishedMatch, isLiveMatch } from '@/lib/fixtures';

export default function MatchCard({ match }: { match: any }) {
  const matchTime = new Date(match.fixture.date);
  const isLive = isLiveMatch(match);
  const isFinished = isFinishedMatch(match);
  
  let statusDisplay = format(matchTime, 'HH:mm');
  if (isLive) statusDisplay = `${match.fixture.status.elapsed}'`;
  if (isFinished) statusDisplay = 'انتهت';

  return (
    <Link href={`/matches/${match.fixture.id}`} className="block">
      <div className="bg-neutral-900 border border-neutral-800 rounded-2xl p-5 hover:border-nor-green/50 transition-all flex flex-col items-center justify-center relative shadow-sm h-full group">
        <div className="absolute inset-0 bg-gradient-to-r from-nor-green/0 via-nor-green/5 to-nor-green/0 opacity-0 group-hover:opacity-100 transition-opacity duration-700 ease-in-out -translate-x-full group-hover:translate-x-full"></div>
        <div className="absolute top-3 right-4">
          <span className="text-xs text-neutral-500 font-readex">{match.league.name}</span>
        </div>

        <div className="w-full flex justify-between items-center mt-4">
          {/* Home Team */}
          <div className="flex flex-col items-center gap-2 flex-1">
            <img src={match.teams.home.logo} alt={match.teams.home.name} className="w-10 h-10 object-contain" />
            <span className="text-sm font-ibm font-medium text-center truncate w-full px-2" title={match.teams.home.name}>{match.teams.home.name}</span>
          </div>

          {/* Score / Time */}
          <div className="flex flex-col items-center justify-center px-4">
            <div className={`text-2xl font-bold font-readex ${isLive ? 'text-nor-green animate-pulse' : 'text-white'}`}>
               {isLive || isFinished ? `${match.goals.home ?? 0} - ${match.goals.away ?? 0}` : statusDisplay}
            </div>
            {isLive && <span className="text-xs text-nor-green mt-1 font-ibm font-medium tracking-wider px-2 py-0.5 bg-nor-green/10 rounded">مباشر</span>}
          </div>

          {/* Away Team */}
          <div className="flex flex-col items-center gap-2 flex-1">
            <img src={match.teams.away.logo} alt={match.teams.away.name} className="w-10 h-10 object-contain" />
            <span className="text-sm font-ibm font-medium text-center truncate w-full px-2" title={match.teams.away.name}>{match.teams.away.name}</span>
          </div>
        </div>
      </div>
    </Link>
  );
}
