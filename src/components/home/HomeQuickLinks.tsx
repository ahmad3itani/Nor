"use client";
import Link from 'next/link';

const quickLinks = [
  { href: '/live', label: 'مباشر', icon: '🔴', desc: 'كل المباريات الحية' },
  { href: '/watchlist', label: 'المتابعة', icon: '📌', desc: 'مباريات فرقي' },
  { href: '/favorites', label: 'المفضلة', icon: '⭐', desc: 'فرق ودوريات' },
  { href: '/matches', label: 'المباريات', icon: '⚽', desc: 'نتائج اليوم' },
  { href: '/analytics', label: 'الإحصائيات', icon: '📊', desc: 'هدافون وصناع' },
  { href: '/transfers', label: 'الانتقالات', icon: '🔄', desc: 'سوق الصفقات' },
  { href: '/injuries', label: 'الإصابات', icon: '🏥', desc: 'تقارير طبية' },
  { href: '/h2h', label: 'مقارنة', icon: '⚔️', desc: 'فريق ضد فريق' },
  { href: '/news', label: 'الأخبار', icon: '📰', desc: 'آخر الأخبار' },
];

export default function HomeQuickLinks() {
  return (
    <div className="grid grid-cols-3 sm:grid-cols-5 lg:grid-cols-9 gap-2 sm:gap-3">
      {quickLinks.map((link) => (
        <Link
          key={link.href}
          href={link.href}
          className="flex flex-col items-center gap-1.5 p-3 sm:p-4 bg-neutral-900 border border-neutral-800 rounded-2xl hover:border-nor-green/50 hover:bg-neutral-900/80 transition-all group text-center"
        >
          <span className="text-xl sm:text-2xl group-hover:scale-110 transition-transform">{link.icon}</span>
          <span className="font-readex font-bold text-xs sm:text-sm text-white group-hover:text-nor-green transition-colors">{link.label}</span>
          <span className="text-[10px] text-neutral-500 font-ibm hidden sm:block">{link.desc}</span>
        </Link>
      ))}
    </div>
  );
}
