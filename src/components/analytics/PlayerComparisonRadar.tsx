"use client";
import React from 'react';
import {
  Chart as ChartJS,
  RadialLinearScale,
  PointElement,
  LineElement,
  Filler,
  Tooltip,
  Legend,
} from 'chart.js';
import { Radar } from 'react-chartjs-2';

ChartJS.register(
  RadialLinearScale,
  PointElement,
  LineElement,
  Filler,
  Tooltip,
  Legend
);

interface ComparisonProps {
  player1: { name: string; stats: number[]; color: string };
  player2: { name: string; stats: number[]; color: string };
}

export default function PlayerComparisonRadar({ player1, player2 }: ComparisonProps) {
  const data = {
    labels: ['الأهداف', 'الصناعة', 'الدقة', 'المراوغات', 'التقييم', 'التسديدات'],
    datasets: [
      {
        label: player1.name,
        data: player1.stats,
        backgroundColor: `${player1.color}33`, // 20% opacity using hex
        borderColor: player1.color,
        borderWidth: 2,
        pointBackgroundColor: player1.color,
      },
      {
        label: player2.name,
        data: player2.stats,
        backgroundColor: `${player2.color}33`, 
        borderColor: player2.color,
        borderWidth: 2,
        pointBackgroundColor: player2.color,
      },
    ],
  };

  const options = {
    scales: {
      r: {
        angleLines: { color: 'rgba(255, 255, 255, 0.1)' },
        grid: { color: 'rgba(255, 255, 255, 0.1)' },
        pointLabels: { color: 'rgba(255, 255, 255, 0.7)', font: { family: 'IBM Plex Sans Arabic' } },
        ticks: { display: false, min: 0, max: 10 }
      }
    },
    plugins: {
      legend: { 
        position: 'bottom' as const,
        labels: { color: 'white', font: { family: 'Readex Pro' } } 
      },
      tooltip: {
        backgroundColor: '#171717',
        titleFont: { family: 'Readex Pro' },
        bodyFont: { family: 'IBM Plex Sans Arabic' },
      }
    }
  };

  return (
    <div className="w-full aspect-square max-h-[300px] flex items-center justify-center relative">
      <Radar data={data} options={options} />
    </div>
  );
}
