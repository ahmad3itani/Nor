"use client";
import React from 'react';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Filler,
  Legend,
} from 'chart.js';
import { Line } from 'react-chartjs-2';

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Filler,
  Legend
);

export default function PlayerRatingChart({ ratings, labels }: { ratings: number[]; labels?: string[] }) {
  const hasLabels = labels && labels.length > 0;

  const options = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        display: false,
      },
      tooltip: {
        backgroundColor: '#171717',
        borderColor: '#00FF85',
        borderWidth: 1,
        titleColor: '#00FF85',
        bodyColor: '#ffffff',
        titleFont: { family: 'Readex Pro', size: 12 },
        bodyFont: { family: 'IBM Plex Sans Arabic', size: 13, weight: 'bold' as const },
        displayColors: false,
        padding: 10,
        callbacks: {
          title: (items: any[]) => items[0]?.label || '',
          label: (item: any) => `التقييم: ${item.raw}`,
        },
      },
    },
    scales: {
      y: {
        min: 5,
        max: 10,
        grid: {
          color: 'rgba(255, 255, 255, 0.05)',
        },
        ticks: {
          color: '#525252',
          font: { size: 10 },
        },
      },
      x: {
        display: hasLabels,
        grid: { display: false },
        ticks: {
          color: '#737373',
          font: { size: 9 },
          maxRotation: 30,
        },
      },
    },
  };

  const data = {
    labels: hasLabels ? labels : ratings.map((_, i) => `م${i + 1}`),
    datasets: [
      {
        fill: true,
        label: 'التقييم',
        data: ratings,
        borderColor: '#00FF85',
        backgroundColor: 'rgba(0, 255, 133, 0.08)',
        tension: 0.4,
        pointBackgroundColor: '#00FF85',
        pointBorderColor: '#080808',
        pointBorderWidth: 2,
        pointRadius: 5,
        pointHoverRadius: 7,
      },
    ],
  };

  return (
    <div className="w-full h-full">
      <Line options={options} data={data} />
    </div>
  );
}
