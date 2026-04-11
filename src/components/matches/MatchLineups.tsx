import Link from 'next/link';

interface LineupProps {
  lineups: any[];
}

export default function LineupPitch({ lineups }: LineupProps) {
  if (!lineups || lineups.length < 2) return <div className="text-center font-readex text-neutral-500 py-10">التشكيلات غير متوفرة بعد</div>;

  const home = lineups[0];
  const away = lineups[1];

  // Helper to parse grid and group players by row
  const groupPlayersByRow = (startXI: any[]) => {
    const rows: { [key: number]: any[] } = {};
    startXI.forEach((item) => {
      const grid = item.player.grid;
      if (!grid) {
        // Fallback if no grid
        const posMap: any = { 'G': 1, 'D': 2, 'M': 3, 'F': 4 };
        const row = posMap[item.player.pos] || 2;
        if (!rows[row]) rows[row] = [];
        rows[row].push(item.player);
        return;
      }
      
      const [rowObj] = grid.split(':').map(Number);
      const row = rowObj;
      if (!rows[row]) rows[row] = [];
      rows[row].push(item.player);
    });

    const sortedRowKeys = Object.keys(rows).map(Number).sort((a, b) => a - b);
    // Away team: row 1 = GK, higher rows = forwards. We want GK at the TOP of the away half,
    // so render in ascending order (GK first = topmost flex item).
    // Home team: same ascending order, but the half uses flex-col-reverse so row 1 (GK) ends up at bottom.
    return sortedRowKeys.map(k => rows[k]);
  };

  const homeFormation = groupPlayersByRow(home.startXI);
  const awayFormation = groupPlayersByRow(away.startXI);

  const PlayerIcon = ({ player, team }: { player: any, team: any }) => (
    <Link href={`/players/${player.id}`} className="flex flex-col items-center group relative z-10 w-16">
      <div 
        className="w-8 h-8 rounded-full border-2 border-white flex items-center justify-center font-bold text-xs text-white shadow-lg transition-transform group-hover:scale-110"
        style={{ backgroundColor: `#${team.team.colors?.player?.primary || '333'}` }}
      >
        {player.number || player.pos}
      </div>
      <span className="text-[10px] text-white font-ibm bg-black/60 px-1.5 py-0.5 rounded mt-1 truncate w-full text-center group-hover:bg-nor-green group-hover:text-black transition-colors">
        {player.name.split(' ').pop()} {/* Show last name */}
      </span>
    </Link>
  );

  return (
    <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6">
      <div className="flex justify-between items-center mb-6">
        <h3 className="text-xl font-bold font-readex border-r-4 border-nor-green pr-3">التشكيلة الأساسية</h3>
        <div className="flex items-center gap-6 text-sm font-ibm font-bold text-neutral-400">
           <span className="flex items-center gap-2"><img src={home.team.logo} alt={home.team.name} className="w-5 h-5"/> {home.formation}</span>
           <span className="text-neutral-600">vs</span>
           <span className="flex items-center gap-2" dir="ltr">{away.formation} <img src={away.team.logo} alt={away.team.name} className="w-5 h-5"/></span>
        </div>
      </div>

      <div className="relative w-full aspect-[2/3] max-w-lg mx-auto bg-[#1a4a2e] rounded-xl border-4 border-white overflow-hidden shadow-inner flex flex-col">
        
        {/* Pitch Lines Decorators */}
        <div className="absolute inset-0 pointer-events-none opacity-40">
           {/* Center Line & Circle */}
           <div className="absolute top-1/2 left-0 w-full h-[2px] bg-white -translate-y-1/2"></div>
           <div className="absolute top-1/2 left-1/2 w-24 h-24 rounded-full border-2 border-white -translate-x-1/2 -translate-y-1/2"></div>
           {/* Penalty Areas */}
           <div className="absolute top-0 left-1/2 w-48 h-24 border-2 border-t-0 border-white -translate-x-1/2"></div>
           <div className="absolute top-0 left-1/2 w-24 h-8 border-2 border-t-0 border-white -translate-x-1/2"></div>
           
           <div className="absolute bottom-0 left-1/2 w-48 h-24 border-2 border-b-0 border-white -translate-x-1/2"></div>
           <div className="absolute bottom-0 left-1/2 w-24 h-8 border-2 border-b-0 border-white -translate-x-1/2"></div>
        </div>

        {/* Away Team Half (Top) */}
        <div className="flex-1 flex flex-col justify-between py-6">
           {awayFormation.map((row, i) => (
             <div key={i} className="flex justify-center gap-2 w-full">
               {row.map((p) => <PlayerIcon key={p.id} player={p} team={away} />)}
             </div>
           ))}
        </div>

        {/* Home Team Half (Bottom) */}
        <div className="flex-1 flex flex-col-reverse justify-between py-6">
           {homeFormation.map((row, i) => (
             <div key={i} className="flex justify-center gap-2 w-full">
               {row.map((p) => <PlayerIcon key={p.id} player={p} team={home} />)}
             </div>
           ))}
        </div>
      </div>

      {/* Substitutes & Coach Board */}
      <div className="mt-8 grid grid-cols-2 gap-8 text-sm font-ibm border-t border-neutral-800 pt-6">
        <div>
          <h4 className="text-nor-green font-bold mb-4 font-readex flex items-center gap-2">
            بدلاء {home.team.name}
          </h4>
          <ul className="space-y-2 text-neutral-300">
             {home.substitutes.map((s: any) => (
               <li key={s.player.id} className="flex justify-between border-b border-neutral-800/50 pb-1">
                 <Link href={`/players/${s.player.id}`} className="hover:text-white transition-colors">{s.player.name}</Link>
                 <span className="text-neutral-500">{s.player.pos}</span>
               </li>
             ))}
          </ul>
          <div className="mt-4 pt-4 border-t border-neutral-800">
             <span className="text-neutral-500">المدرب: </span>
             <span className="font-bold">{home.coach.name}</span>
          </div>
        </div>

        <div>
           <h4 className="text-nor-green font-bold mb-4 font-readex flex items-center gap-2">
            بدلاء {away.team.name}
          </h4>
          <ul className="space-y-2 text-neutral-300">
             {away.substitutes.map((s: any) => (
               <li key={s.player.id} className="flex justify-between border-b border-neutral-800/50 pb-1 text-left" dir="ltr">
                 <Link href={`/players/${s.player.id}`} className="hover:text-white transition-colors">{s.player.name}</Link>
                 <span className="text-neutral-500">{s.player.pos}</span>
               </li>
             ))}
          </ul>
          <div className="mt-4 pt-4 border-t border-neutral-800 text-left" dir="ltr">
             <span className="text-neutral-500">Coach: </span>
             <span className="font-bold">{away.coach.name}</span>
          </div>
        </div>
      </div>
      
    </div>
  );
}
