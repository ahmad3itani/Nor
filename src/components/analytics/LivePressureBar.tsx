"use client";
import React, { useEffect, useState } from 'react';

interface LivePressureBarProps {
  homeTeamName: string;
  awayTeamName: string;
  homeValue: number; // e.g. Possession or xG or Dangerous Attacks
  awayValue: number;
  label: string;
}

export default function LivePressureBar({
  homeTeamName,
  awayTeamName,
  homeValue,
  awayValue,
  label
}: LivePressureBarProps) {
  const [animatedHome, setAnimatedHome] = useState(50);

  useEffect(() => {
    // Small delay for initial animation
    const total = homeValue + awayValue;
    const target = total > 0 ? (homeValue / total) * 100 : 50;
    
    // Add a slight variance every few seconds to simulate "Live" shaking
    const interval = setInterval(() => {
      const variance = (Math.random() - 0.5) * 2; // ±1%
      setAnimatedHome(target + variance);
    }, 2000);

    setAnimatedHome(target);
    return () => clearInterval(interval);
  }, [homeValue, awayValue]);

  return (
    <div className="w-full flex flex-col gap-2">
      <div className="flex justify-between items-center text-xs font-ibm font-bold">
         <span className="text-nor-white">{homeTeamName}</span>
         <span className="text-neutral-500 font-readex bg-neutral-900 border border-neutral-800 px-3 py-1 rounded-full shadow-sm">
            {label} 
            <span className="w-1.5 h-1.5 rounded-full bg-nor-green inline-block ml-2 animate-pulse"></span>
         </span>
         <span className="text-nor-white">{awayTeamName}</span>
      </div>
      
      <div className="relative w-full h-3 bg-neutral-800 rounded-full overflow-hidden flex shadow-inner">
         <div 
            className="h-full bg-nor-green transition-all duration-1000 ease-out"
            style={{ width: `${animatedHome}%` }}
         >
         </div>
         <div 
            className="h-full bg-white transition-all duration-1000 ease-out"
            style={{ width: `${100 - animatedHome}%` }}
         >
         </div>
         
         <div className="absolute top-0 bottom-0 left-1/2 w-0.5 bg-neutral-900/50 -translate-x-1/2 z-10"></div>
      </div>
      
      <div className="flex justify-between items-center text-xs font-readex text-neutral-400 mt-1">
         <span>{Math.round(homeValue)}{label.includes('%') ? '%' : ''}</span>
         <span>{Math.round(awayValue)}{label.includes('%') ? '%' : ''}</span>
      </div>
    </div>
  );
}
