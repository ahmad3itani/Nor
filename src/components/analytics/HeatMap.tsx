interface HeatMapProps {
  position?: string;
  stats?: any;
}

export default function HeatMap({ position, stats }: HeatMapProps) {
  // A pseudo "Zonal Performance Map" that highlights areas based on position.
  // Attackers get hot zones in the penalty box.
  // Defenders get hot zones near their own box.
  // Midfielders get hot zones in the center.
  
  const getZoneColors = () => {
    switch(position) {
      case 'Attacker':
        return 'bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-nor-green/60 via-nor-green/20 to-transparent';
      case 'Midfielder':
        return 'bg-[radial-gradient(ellipse_at_center,_var(--tw-gradient-stops))] from-nor-green/60 via-nor-green/20 to-transparent';
      case 'Defender':
        return 'bg-[radial-gradient(ellipse_at_bottom,_var(--tw-gradient-stops))] from-nor-green/60 via-nor-green/20 to-transparent';
      case 'Goalkeeper':
        return 'bg-[radial-gradient(ellipse_at_bottom,_var(--tw-gradient-stops))] from-nor-green/80 via-transparent to-transparent';
      default:
        return 'bg-transparent';
    }
  };

  const getIntensityLabel = () => {
     if (!stats) return 'متوسط';
     const rating = parseFloat(stats.games.rating) || 0;
     if (rating >= 7.5) return 'عالي جداً (مؤثر)';
     if (rating >= 7.0) return 'مرتفع';
     return 'متوسط';
  }

  return (
    <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 h-full flex flex-col items-center">
      <h3 className="text-xl font-bold font-readex mb-6 border-r-4 border-nor-green pr-3 w-full">الخريطة الحرارية للمناطق (Zonal Map)</h3>
      
      {/* Pitch Skeleton */}
      <div className="relative w-full aspect-[2/3] max-w-[250px] bg-[#1a4a2e] rounded-xl border-2 border-white overflow-hidden shadow-inner flex flex-col">
        {/* The Heat Gradient Overlay */}
        <div className={`absolute inset-0 z-10 ${getZoneColors()}`}></div>

        {/* Pitch Lines Decorators */}
        <div className="absolute inset-0 pointer-events-none opacity-40 z-0">
           {/* Center Line & Circle */}
           <div className="absolute top-1/2 left-0 w-full h-[1px] bg-white -translate-y-1/2"></div>
           <div className="absolute top-1/2 left-1/2 w-16 h-16 rounded-full border border-white -translate-x-1/2 -translate-y-1/2"></div>
           {/* Penalty Areas */}
           <div className="absolute top-0 left-1/2 w-32 h-16 border border-t-0 border-white -translate-x-1/2"></div>
           <div className="absolute top-0 left-1/2 w-16 h-6 border border-t-0 border-white -translate-x-1/2"></div>
           
           <div className="absolute bottom-0 left-1/2 w-32 h-16 border border-b-0 border-white -translate-x-1/2"></div>
           <div className="absolute bottom-0 left-1/2 w-16 h-6 border border-b-0 border-white -translate-x-1/2"></div>
        </div>
      </div>

      <div className="mt-6 w-full space-y-3 font-ibm text-sm">
         <div className="flex justify-between items-center text-neutral-300">
           <span className="text-neutral-500">كثافة التأثير:</span>
           <span className="text-white font-bold">{getIntensityLabel()}</span>
         </div>
         <p className="text-xs text-neutral-500 text-center leading-relaxed">
            تعتمد الخريطة الحرارية للمسافات على المناطق المتوقعة استناداً للأداء والاحصائيات الشاملة في الدوري.
         </p>
      </div>
    </div>
  );
}
