"use client";
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

export default function PlayerRadar({ }: { stats?: any }) {
  const data = {
    labels: ['الأهداف', 'صناعة الأهداف', 'دقة التمرير', 'المراوغات', 'التقييم', 'التسديدات'],
    datasets: [
      {
        label: 'اللاعب (عينة)',
        data: [8, 6, 8.5, 7, 8.1, 9],
        backgroundColor: 'rgba(0, 255, 133, 0.2)',
        borderColor: 'rgba(0, 255, 133, 1)',
        borderWidth: 2,
        pointBackgroundColor: 'rgba(0, 255, 133, 1)',
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
      legend: { labels: { color: 'white', font: { family: 'Readex Pro' } } }
    }
  };

  return <Radar data={data} options={options} />;
}
