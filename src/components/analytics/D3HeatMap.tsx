"use client";
import React, { useEffect, useRef } from 'react';
import * as d3 from 'd3';

interface D3HeatMapProps {
  playerPhoto: string;
  position: string;
  intensity: number; // 0–10
}

type Zone = { cx: number; cy: number; rx: number; ry: number; weight: number };

function getZones(position: string, W: number, H: number): Zone[] {
  if (position.includes('Goalkeeper') || position === 'G' || position === 'GK') {
    return [
      { cx: W / 2,      cy: H - 35,      rx: 55,  ry: 22, weight: 1.0 },
      { cx: W / 2 - 35, cy: H - 55,      rx: 22,  ry: 18, weight: 0.55 },
      { cx: W / 2 + 35, cy: H - 55,      rx: 22,  ry: 18, weight: 0.55 },
    ];
  }
  if (position.includes('Defender') || position === 'D' || position === 'CB' || position === 'LB' || position === 'RB') {
    return [
      { cx: W / 2,      cy: H * 0.80,    rx: 85,  ry: 42, weight: 1.0 },
      { cx: W / 2 - 65, cy: H * 0.73,    rx: 32,  ry: 28, weight: 0.70 },
      { cx: W / 2 + 65, cy: H * 0.73,    rx: 32,  ry: 28, weight: 0.70 },
      { cx: W / 2,      cy: H * 0.63,    rx: 55,  ry: 25, weight: 0.35 },
    ];
  }
  if (position.includes('Midfielder') || position === 'M' || position === 'CM' || position === 'CAM' || position === 'CDM') {
    return [
      { cx: W / 2,      cy: H * 0.50,    rx: 72,  ry: 58, weight: 1.0 },
      { cx: W / 2 - 58, cy: H * 0.46,    rx: 28,  ry: 36, weight: 0.70 },
      { cx: W / 2 + 58, cy: H * 0.46,    rx: 28,  ry: 36, weight: 0.70 },
      { cx: W / 2,      cy: H * 0.36,    rx: 52,  ry: 30, weight: 0.60 },
      { cx: W / 2,      cy: H * 0.65,    rx: 45,  ry: 28, weight: 0.40 },
    ];
  }
  // Attacker (default)
  return [
    { cx: W / 2,      cy: H * 0.17,    rx: 65,  ry: 45, weight: 1.0 },
    { cx: W / 2 - 55, cy: H * 0.25,    rx: 28,  ry: 26, weight: 0.80 },
    { cx: W / 2 + 55, cy: H * 0.25,    rx: 28,  ry: 26, weight: 0.80 },
    { cx: W / 2,      cy: H * 0.38,    rx: 48,  ry: 32, weight: 0.50 },
  ];
}

function heatColor(w: number): string {
  if (w > 0.78) return `rgba(255, 45, 0, ${(w * 0.88).toFixed(2)})`;
  if (w > 0.55) return `rgba(255, 140, 0, ${(w * 0.82).toFixed(2)})`;
  if (w > 0.32) return `rgba(255, 220, 0, ${(w * 0.75).toFixed(2)})`;
  return `rgba(0, 255, 133, ${(w * 0.60).toFixed(2)})`;
}

export default function D3HeatMap({ playerPhoto, position, intensity }: D3HeatMapProps) {
  const svgRef = useRef<SVGSVGElement>(null);

  useEffect(() => {
    if (!svgRef.current) return;

    const svg = d3.select(svgRef.current);
    svg.selectAll('*').remove();

    const W = 300;
    const H = 420;

    svg
      .attr('viewBox', `0 0 ${W} ${H}`)
      .attr('preserveAspectRatio', 'xMidYMid meet')
      .style('border-radius', '12px');

    // ── Background pitch ────────────────────────────────────────────────
    // Alternating stripes
    const stripeH = H / 8;
    for (let i = 0; i < 8; i++) {
      svg.append('rect')
        .attr('x', 0).attr('y', i * stripeH)
        .attr('width', W).attr('height', stripeH)
        .attr('fill', i % 2 === 0 ? '#0d3318' : '#0f3d1e');
    }

    // ── Defs: blur filter ────────────────────────────────────────────────
    const defs = svg.append('defs');

    const filterId = 'heatBlur';
    const filter = defs.append('filter')
      .attr('id', filterId)
      .attr('x', '-40%').attr('y', '-40%')
      .attr('width', '180%').attr('height', '180%')
      .attr('color-interpolation-filters', 'sRGB');
    filter.append('feGaussianBlur')
      .attr('in', 'SourceGraphic')
      .attr('stdDeviation', '20');

    // ── Heat layer (blurred) ─────────────────────────────────────────────
    const heatG = svg.append('g').attr('filter', `url(#${filterId})`);

    const zones = getZones(position, W, H);
    const totalPoints = Math.max(30, Math.round(intensity * 18));
    const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));

    zones.forEach((z) => {
      const n = Math.round(totalPoints * z.weight);
      for (let i = 0; i < n; i++) {
        // Box–Muller-ish distribution: sum of 2 uniforms → triangle → more centre-heavy
        const u1 = (Math.random() + Math.random()) / 2;
        const theta = Math.random() * 2 * Math.PI;
        const px = clamp(z.cx + Math.cos(theta) * u1 * z.rx, 5, W - 5);
        const py = clamp(z.cy + Math.sin(theta) * u1 * z.ry, 5, H - 5);
        const distFrac = Math.sqrt(
          Math.pow((px - z.cx) / z.rx, 2) + Math.pow((py - z.cy) / z.ry, 2)
        );
        const w = clamp((1 - distFrac) * z.weight * (intensity / 10), 0, 1);
        const r = 14 + w * 22;

        heatG.append('circle')
          .attr('cx', px).attr('cy', py).attr('r', r)
          .style('fill', heatColor(w))
          .style('opacity', String(clamp(w * 0.9, 0.05, 0.9)));
      }
    });

    // ── Pitch lines (on top of heat) ─────────────────────────────────────
    const g = svg.append('g')
      .style('stroke', 'rgba(255,255,255,0.30)')
      .style('stroke-width', '1.5')
      .style('fill', 'none');

    // Outer border
    g.append('rect').attr('x', 8).attr('y', 8).attr('width', W - 16).attr('height', H - 16).attr('rx', 3);
    // Halfway line
    g.append('line').attr('x1', 8).attr('y1', H / 2).attr('x2', W - 8).attr('y2', H / 2);
    // Centre circle
    g.append('circle').attr('cx', W / 2).attr('cy', H / 2).attr('r', 40);
    g.append('circle').attr('cx', W / 2).attr('cy', H / 2).attr('r', 2.5)
      .style('fill', 'rgba(255,255,255,0.5)').style('stroke', 'none');

    // Top penalty area + goal area
    g.append('rect').attr('x', W / 2 - 62).attr('y', 8).attr('width', 124).attr('height', 68);
    g.append('rect').attr('x', W / 2 - 32).attr('y', 8).attr('width', 64).attr('height', 24);
    // Top penalty spot
    g.append('circle').attr('cx', W / 2).attr('cy', 90).attr('r', 2)
      .style('fill', 'rgba(255,255,255,0.4)').style('stroke', 'none');

    // Bottom penalty area + goal area
    g.append('rect').attr('x', W / 2 - 62).attr('y', H - 76).attr('width', 124).attr('height', 68);
    g.append('rect').attr('x', W / 2 - 32).attr('y', H - 32).attr('width', 64).attr('height', 24);
    // Bottom penalty spot
    g.append('circle').attr('cx', W / 2).attr('cy', H - 90).attr('r', 2)
      .style('fill', 'rgba(255,255,255,0.4)').style('stroke', 'none');
  }, [position, intensity]);

  return (
    <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-6 shadow-lg">
      <div className="flex items-center gap-3 mb-4">
        <img
          src={playerPhoto}
          alt=""
          className="w-10 h-10 rounded-full object-cover border-2 border-nor-green/40 shrink-0"
        />
        <h3 className="text-lg font-bold font-readex border-r-4 border-nor-green pr-3">الخريطة الحرارية</h3>
      </div>

      <div className="relative w-full max-w-[260px] mx-auto" style={{ aspectRatio: '5/7' }}>
        {/* SVG pitch + heat only — no photo overlay */}
        <svg ref={svgRef} className="w-full h-full rounded-xl overflow-hidden" />

        {/* Badge */}
        <div className="absolute top-2 right-2 z-20 flex items-center gap-1.5 bg-black/70 backdrop-blur-sm border border-neutral-700/60 px-2.5 py-1 rounded-full text-[11px] font-ibm font-bold">
          <span className="w-1.5 h-1.5 rounded-full bg-red-500 animate-pulse" />
          مناطق التأثير
        </div>
      </div>

      {/* Intensity legend */}
      <div className="mt-4 flex items-center gap-2 text-[11px] font-ibm text-neutral-500" dir="ltr">
        <span className="shrink-0">منخفض</span>
        <div
          className="flex-1 h-1.5 rounded-full"
          style={{ background: 'linear-gradient(to right, #00FF85, #ffdc00, #ff8c00, #ff2d00)' }}
        />
        <span className="shrink-0">مرتفع</span>
      </div>
    </div>
  );
}
