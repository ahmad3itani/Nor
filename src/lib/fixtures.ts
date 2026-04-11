import { getAllLeagueIds } from '@/lib/config/leagues';

export const LIVE_MATCH_STATUSES = ['1H', 'HT', '2H', 'ET', 'BT', 'P', 'INT', 'LIVE'];
export const UPCOMING_MATCH_STATUSES = ['NS', 'TBD'];
export const FINISHED_MATCH_STATUSES = ['FT', 'AET', 'PEN'];

export function isLiveMatch(match: any) {
  return LIVE_MATCH_STATUSES.includes(match?.fixture?.status?.short);
}

export function isUpcomingMatch(match: any) {
  return UPCOMING_MATCH_STATUSES.includes(match?.fixture?.status?.short);
}

export function isFinishedMatch(match: any) {
  return FINISHED_MATCH_STATUSES.includes(match?.fixture?.status?.short);
}

export function filterSupportedLeagueFixtures(fixtures: any[]) {
  const supportedLeagueIds = new Set(getAllLeagueIds().map(Number));
  return fixtures.filter((fixture) => supportedLeagueIds.has(fixture?.league?.id));
}

export function sortFixtures(fixtures: any[]) {
  return [...fixtures].sort((a, b) => {
    const aLive = isLiveMatch(a);
    const bLive = isLiveMatch(b);
    if (aLive !== bLive) return aLive ? -1 : 1;

    const aUpcoming = isUpcomingMatch(a);
    const bUpcoming = isUpcomingMatch(b);
    if (aUpcoming !== bUpcoming) return aUpcoming ? -1 : 1;

    const aTime = new Date(a?.fixture?.date || 0).getTime();
    const bTime = new Date(b?.fixture?.date || 0).getTime();

    if (aUpcoming && bUpcoming) return aTime - bTime;
    return bTime - aTime;
  });
}
