import Link from 'next/link';

export interface BreadcrumbItem {
  label: string;
  href?: string;
}

interface BreadcrumbsProps {
  items: BreadcrumbItem[];
  className?: string;
}

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL || 'https://goaliador.com';

export default function Breadcrumbs({ items, className = '' }: BreadcrumbsProps) {
  // JSON-LD BreadcrumbList
  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: [
      { '@type': 'ListItem', position: 1, name: 'الرئيسية', item: SITE_URL },
      ...items.map((item, i) => ({
        '@type': 'ListItem',
        position: i + 2,
        name: item.label,
        ...(item.href ? { item: `${SITE_URL}${item.href}` } : {}),
      })),
    ],
  };

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
      <nav aria-label="breadcrumb" className={`flex items-center gap-1.5 text-xs font-ibm text-neutral-500 flex-wrap ${className}`}>
        <Link href="/" className="hover:text-nor-green transition-colors">الرئيسية</Link>
        {items.map((item, i) => (
          <span key={i} className="flex items-center gap-1.5">
            <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="shrink-0 rotate-180">
              <path d="m9 18 6-6-6-6"/>
            </svg>
            {item.href ? (
              <Link href={item.href} className="hover:text-nor-green transition-colors">{item.label}</Link>
            ) : (
              <span className="text-neutral-300">{item.label}</span>
            )}
          </span>
        ))}
      </nav>
    </>
  );
}
