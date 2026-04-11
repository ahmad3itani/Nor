interface StatRowProps {
  label: string;
  homeValue: string | number | null;
  awayValue: string | number | null;
}

function StatRow({ label, homeValue, awayValue }: StatRowProps) {
  const hVal = homeValue === null ? 0 : parseFloat(homeValue.toString().replace('%', ''));
  const aVal = awayValue === null ? 0 : parseFloat(awayValue.toString().replace('%', ''));
  const total = hVal + aVal || 1; // prevent div by zero
  const homePercent = (hVal / total) * 100;

  return (
    <div className="flex flex-col gap-1.5 font-ibm text-sm mb-4">
      <div className="flex justify-between items-center text-neutral-300">
        <span className="font-bold">{homeValue ?? 0}</span>
        <span className="text-neutral-500 font-readex">{label}</span>
        <span className="font-bold">{awayValue ?? 0}</span>
      </div>
      <div className="h-2 w-full bg-neutral-800 rounded-full flex overflow-hidden">
         <div className="bg-nor-green h-full" style={{ width: `${homePercent}%`}}></div>
         <div className="bg-white h-full" style={{ width: `${100 - homePercent}%`}}></div>
      </div>
    </div>
  );
}

export default function MatchStats({ statistics }: { statistics: any[] }) {
  if (!statistics || statistics.length < 2) return <div className="text-center font-readex text-neutral-500 py-10">البيانات غير متوفرة بعد</div>;

  const homeStats = statistics[0].statistics;
  const awayStats = statistics[1].statistics;

  const extractStat = (type: string, statsData: any[]) => {
    const s = statsData.find(st => st.type === type);
    return s ? s.value : 0;
  };

  const getStatPair = (typeEn: string, typeAr: string) => ({
    label: typeAr,
    home: extractStat(typeEn, homeStats),
    away: extractStat(typeEn, awayStats)
  });

  const coreStats = [
    getStatPair('Ball Possession', 'الاستحواذ على الكرة'),
    getStatPair('Total Shots', 'إجمالي التسديدات'),
    getStatPair('Shots on Goal', 'التسديدات على المرمى'),
    getStatPair('Shots off Goal', 'التسديدات خارج المرمى'),
    getStatPair('Blocked Shots', 'تسديدات تم اعتراضها'),
    getStatPair('Passes %', 'دقة التمرير'),
    getStatPair('Total passes', 'إجمالي التمريرات'),
    getStatPair('Passes accurate', 'تمريرات ناجحة'),
    getStatPair('Fouls', 'أخطاء'),
    getStatPair('Corner Kicks', 'ركلات ركنية'),
    getStatPair('Offsides', 'تسلل'),
    getStatPair('Yellow Cards', 'بطاقات صفراء'),
    getStatPair('Red Cards', 'بطاقات حمراء'),
    getStatPair('Goalkeeper Saves', 'تصديات الحارس')
  ];

  return (
    <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6">
      <h3 className="text-xl font-bold font-readex mb-8 border-r-4 border-nor-green pr-3">تحليل أداء الفريقين</h3>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-x-12">
        <div className="space-y-2">
          {coreStats.slice(0, 7).map((s) => (
             <StatRow key={s.label} label={s.label} homeValue={s.home} awayValue={s.away} />
          ))}
        </div>
        <div className="space-y-2">
           {coreStats.slice(7).map((s) => (
             <StatRow key={s.label} label={s.label} homeValue={s.home} awayValue={s.away} />
          ))}
        </div>
      </div>
    </div>
  );
}
