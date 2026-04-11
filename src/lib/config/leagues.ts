// Top 5 European leagues
export const TOP_5_LEAGUES = [
  { id: '39', name: 'الدوري الإنجليزي', nameEn: 'Premier League', logo: 'https://media.api-sports.io/football/leagues/39.png', country: 'إنجلترا', flag: '🏴󠁧󠁢󠁥󠁮󠁧󠁿' },
  { id: '140', name: 'الدوري الإسباني', nameEn: 'La Liga', logo: 'https://media.api-sports.io/football/leagues/140.png', country: 'إسبانيا', flag: '🇪🇸' },
  { id: '135', name: 'الدوري الإيطالي', nameEn: 'Serie A', logo: 'https://media.api-sports.io/football/leagues/135.png', country: 'إيطاليا', flag: '🇮🇹' },
  { id: '78', name: 'الدوري الألماني', nameEn: 'Bundesliga', logo: 'https://media.api-sports.io/football/leagues/78.png', country: 'ألمانيا', flag: '🇩🇪' },
  { id: '61', name: 'الدوري الفرنسي', nameEn: 'Ligue 1', logo: 'https://media.api-sports.io/football/leagues/61.png', country: 'فرنسا', flag: '🇫🇷' },
];

// Continental competitions
export const CONTINENTAL_LEAGUES = [
  { id: '2', name: 'دوري أبطال أوروبا', nameEn: 'Champions League', logo: 'https://media.api-sports.io/football/leagues/2.png', country: 'أوروبا', flag: '🇪🇺' },
  { id: '3', name: 'الدوري الأوروبي', nameEn: 'Europa League', logo: 'https://media.api-sports.io/football/leagues/3.png', country: 'أوروبا', flag: '🇪🇺' },
  { id: '848', name: 'دوري المؤتمر الأوروبي', nameEn: 'Conference League', logo: 'https://media.api-sports.io/football/leagues/848.png', country: 'أوروبا', flag: '🇪🇺' },
];

// Other European leagues
export const OTHER_EUROPEAN_LEAGUES = [
  { id: '88', name: 'الدوري الهولندي', nameEn: 'Eredivisie', logo: 'https://media.api-sports.io/football/leagues/88.png', country: 'هولندا', flag: '🇳🇱' },
  { id: '94', name: 'الدوري البرتغالي', nameEn: 'Liga Portugal', logo: 'https://media.api-sports.io/football/leagues/94.png', country: 'البرتغال', flag: '🇵🇹' },
  { id: '144', name: 'الدوري البلجيكي', nameEn: 'Belgian Pro League', logo: 'https://media.api-sports.io/football/leagues/144.png', country: 'بلجيكا', flag: '🇧🇪' },
  { id: '203', name: 'الدوري التركي', nameEn: 'Super Lig', logo: 'https://media.api-sports.io/football/leagues/203.png', country: 'تركيا', flag: '🇹🇷' },
  { id: '179', name: 'الدوري الاسكتلندي', nameEn: 'Scottish Premiership', logo: 'https://media.api-sports.io/football/leagues/179.png', country: 'اسكتلندا', flag: '🏴󠁧󠁢󠁳󠁣󠁴󠁿' },
];

// Arab & Asian leagues
export const ARAB_LEAGUES = [
  { id: '307', name: 'دوري روشن السعودي', nameEn: 'Saudi Pro League', logo: 'https://media.api-sports.io/football/leagues/307.png', country: 'السعودية', flag: '🇸🇦' },
  { id: '233', name: 'الدوري المصري', nameEn: 'Egyptian Premier League', logo: 'https://media.api-sports.io/football/leagues/233.png', country: 'مصر', flag: '🇪🇬' },
  { id: '551', name: 'دوري نجوم قطر', nameEn: 'Qatar Stars League', logo: 'https://media.api-sports.io/football/leagues/551.png', country: 'قطر', flag: '🇶🇦' },
  { id: '325', name: 'الدوري الإماراتي', nameEn: 'UAE Pro League', logo: 'https://media.api-sports.io/football/leagues/325.png', country: 'الإمارات', flag: '🇦🇪' },
];

// South American leagues
export const SOUTH_AMERICAN_LEAGUES = [
  { id: '71', name: 'الدوري البرازيلي', nameEn: 'Serie A Brazil', logo: 'https://media.api-sports.io/football/leagues/71.png', country: 'البرازيل', flag: '🇧🇷' },
  { id: '128', name: 'الدوري الأرجنتيني', nameEn: 'Liga Profesional', logo: 'https://media.api-sports.io/football/leagues/128.png', country: 'الأرجنتين', flag: '🇦🇷' },
  { id: '13', name: 'كوبا ليبرتادوريس', nameEn: 'Copa Libertadores', logo: 'https://media.api-sports.io/football/leagues/13.png', country: 'أمريكا الجنوبية', flag: '🌎' },
];

// All leagues flat array (used by LeagueSwitcher and fixtures API)
export const SUPPORTED_LEAGUES = [
  ...TOP_5_LEAGUES,
  ...ARAB_LEAGUES,
  ...CONTINENTAL_LEAGUES,
  ...OTHER_EUROPEAN_LEAGUES,
  ...SOUTH_AMERICAN_LEAGUES,
];

// League categories for organized display
export const LEAGUE_CATEGORIES = [
  { label: 'الدوريات الخمس الكبرى', leagues: TOP_5_LEAGUES },
  { label: 'البطولات القارية', leagues: CONTINENTAL_LEAGUES },
  { label: 'الدوريات العربية', leagues: ARAB_LEAGUES },
  { label: 'دوريات أوروبية أخرى', leagues: OTHER_EUROPEAN_LEAGUES },
  { label: 'أمريكا الجنوبية', leagues: SOUTH_AMERICAN_LEAGUES },
];

export function getLeagueMap(id: string) {
  return SUPPORTED_LEAGUES.find(l => l.id === id) || SUPPORTED_LEAGUES[0];
}

export function getAllLeagueIds(): string[] {
  return SUPPORTED_LEAGUES.map(l => l.id);
}
