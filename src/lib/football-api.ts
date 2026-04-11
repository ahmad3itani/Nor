const API_FOOTBALL_KEY = process.env.API_FOOTBALL_KEY || '';
const API_FOOTBALL_HOST = process.env.API_FOOTBALL_HOST || 'api-football-v1.p.rapidapi.com';

const HEADERS = {
  'x-rapidapi-key': API_FOOTBALL_KEY,
  'x-rapidapi-host': API_FOOTBALL_HOST
};

const BASE_URL = 'https://v3.football.api-sports.io';

async function fetchApi(endpoint: string, params: Record<string, string> = {}) {
  const url = new URL(`${BASE_URL}${endpoint}`);
  Object.keys(params).forEach(key => url.searchParams.append(key, params[key]));

  const response = await fetch(url.toString(), {
    method: 'GET',
    headers: HEADERS,
    next: { revalidate: 30 } // Cache for 30s by default
  });

  if (!response.ok) {
    throw new Error(`API Football Error: ${response.statusText}`);
  }

  const data = await response.json();
  return data.response;
}

// Add proper season logic
export function getCurrentSeason() {
  const date = new Date();
  const year = date.getFullYear();
  const month = date.getMonth(); // 0 is January
  // European seasons start in August (month 7)
  return month < 7 ? (year - 1).toString() : year.toString();
}

export const footballApi = {
  // Live & Fixtures
  getLiveMatches: () => fetchApi('/fixtures', { live: 'all' }),
  getStandings: (league: string, season: string) => fetchApi('/standings', { league, season }),
  getPlayerStats: (id: string, season: string) => fetchApi('/players', { id, season }),
  getLeagueFixtures: (league: string, season: string) => fetchApi('/fixtures', { league, season }),
  getDailyFixtures: (date: string) => fetchApi('/fixtures', { date }),
  getFixtureDetails: (id: string) => fetchApi('/fixtures', { id }),
  getFixtureStatistics: (id: string) => fetchApi('/fixtures/statistics', { fixture: id }),
  getFixtureEvents: (id: string) => fetchApi('/fixtures/events', { fixture: id }),
  getFixtureLineups: (id: string) => fetchApi('/fixtures/lineups', { fixture: id }),
  getFixturePredictions: (id: string) => fetchApi('/predictions', { fixture: id }),
  getHeadToHead: (h2h: string) => fetchApi('/fixtures/headtohead', { h2h }),
  getFixtureRounds: (league: string, season: string) => fetchApi('/fixtures/rounds', { league, season }),
  
  // Teams
  searchTeams: (search: string, league?: string, season?: string) => fetchApi('/teams', {
    search,
    ...(league ? { league } : {}),
    ...(season ? { season } : {}),
  }),
  getTeamDetails: (id: string) => fetchApi('/teams', { id }),
  getTeamStats: (team: string, league: string, season: string) => fetchApi('/teams/statistics', { team, league, season }),
  getTeamFixtures: (team: string, season: string, last: number = 5) => fetchApi('/fixtures', { team, season, last: last.toString() }),
  getNextTeamFixtures: (team: string, season: string, next: number = 5) => fetchApi('/fixtures', { team, season, next: next.toString() }),
  getTeamSquad: (team: string) => fetchApi('/players/squads', { team }),
  getTeamSeasons: (team: string) => fetchApi('/teams/seasons', { team }),
  
  // Players & Analytics
  searchPlayers: (search: string) => fetchApi('/players/profiles', { search }),
  getTopScorers: (league: string, season: string) => fetchApi('/players/topscorers', { league, season }),
  getTopAssists: (league: string, season: string) => fetchApi('/players/topassists', { league, season }),
  getTopRedCards: (league: string, season: string) => fetchApi('/players/topredcards', { league, season }),
  getTopYellowCards: (league: string, season: string) => fetchApi('/players/topyellowcards', { league, season }),
  
  // Transfers & Injuries
  getTransfers: (team?: string) => fetchApi('/transfers', team ? { team } : {}),
  getPlayerTransfers: (player: string) => fetchApi('/transfers', { player }),
  getTeamTransfers: (team: string) => fetchApi('/transfers', { team }),
  getInjuries: (league?: string, season?: string) => fetchApi('/injuries', league ? { league, season: season || getCurrentSeason() } : {}),
  getSidelined: (league?: string, season?: string) => fetchApi('/sidelined', league ? { league, season: season || getCurrentSeason() } : {}),
  
  // Odds
  getOdds: (fixture: string) => fetchApi('/odds', { fixture }),
  getOddsLive: () => fetchApi('/odds/live', {}),
  getOddsMapping: (fixture: string) => fetchApi('/odds/mapping', { fixture }),
  
  // Coaches & Trophies
  getCoachDetails: (id: string) => fetchApi('/coachs', { id }),
  getPlayerTrophies: (player: string) => fetchApi('/trophies', { player }),
  getCoachTrophies: (coach: string) => fetchApi('/trophies', { coach }),
  
  // Leagues & Countries
  getLeagues: () => fetchApi('/leagues', {}),
  getCountries: () => fetchApi('/countries', {}),
  getVenue: (id: string) => fetchApi('/venues', { id }),
};
