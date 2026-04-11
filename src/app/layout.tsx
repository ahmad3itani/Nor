import type { Metadata } from 'next';
import localFont from 'next/font/local';
import './globals.css';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import LiveTicker from '@/components/layout/LiveTicker';
import Providers from '@/components/providers/Providers';

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL || 'https://nor.com';

const ibmPlex = localFont({
  src: './fonts/GeistVF.woff',
  variable: '--font-ibm',
  display: 'swap',
});

const amiri = localFont({
  src: './fonts/GeistMonoVF.woff',
  variable: '--font-amiri',
  display: 'swap',
});

const readexPro = localFont({
  src: './fonts/GeistVF.woff',
  variable: '--font-readex',
  display: 'swap',
});

const almarai = localFont({
  src: './fonts/GeistVF.woff',
  variable: '--font-almarai',
  display: 'swap',
});

export const metadata: Metadata = {
  title: {
    default: 'نور | منصة كرة القدم الذكية',
    template: '%s | نور',
  },
  manifest: '/manifest.json',
  icons: {
    icon: '/favicon.svg',
    shortcut: '/favicon.svg',
    apple: '/favicon.svg',
  },
  description: 'منصة عربية ذكية لكرة القدم. أخبار لحظية، نتائج مباشرة، إحصائيات شاملة، وتحليلات بالذكاء الاصطناعي.',
  keywords: ['كرة القدم', 'أخبار رياضية', 'نتائج مباريات', 'إحصائيات', 'دوري أبطال أوروبا', 'الدوري الإنجليزي', 'الدوري السعودي', 'هدافون'],
  metadataBase: new URL(SITE_URL),
  alternates: { canonical: SITE_URL },
  openGraph: {
    title: 'نور | منصة كرة القدم الذكية',
    description: 'منصة عربية ذكية لكرة القدم. أخبار لحظية، نتائج مباشرة، وتحليلات بالذكاء الاصطناعي.',
    url: SITE_URL,
    type: 'website',
    locale: 'ar_SA',
    siteName: 'نور - nōr',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'نور | منصة كرة القدم الذكية',
    description: 'أخبار كرة القدم، نتائج مباشرة، وإحصائيات شاملة بالعربية.',
    site: '@norFootball',
  },
  robots: {
    index: true,
    follow: true,
    googleBot: { index: true, follow: true, 'max-image-preview': 'large', 'max-snippet': -1 },
  },
  category: 'sports',
};

// Organisation + WebSite JSON-LD (injected once in the root layout)
const orgJsonLd = {
  '@context': 'https://schema.org',
  '@graph': [
    {
      '@type': 'Organization',
      '@id': `${SITE_URL}/#organization`,
      name: 'نور - nōr',
      url: SITE_URL,
      logo: { '@type': 'ImageObject', url: `${SITE_URL}/logo.png` },
      sameAs: [],
    },
    {
      '@type': 'WebSite',
      '@id': `${SITE_URL}/#website`,
      url: SITE_URL,
      name: 'نور - nōr',
      description: 'منصة عربية ذكية لكرة القدم',
      inLanguage: 'ar',
      publisher: { '@id': `${SITE_URL}/#organization` },
      potentialAction: {
        '@type': 'SearchAction',
        target: { '@type': 'EntryPoint', urlTemplate: `${SITE_URL}/news?q={search_term_string}` },
        'query-input': 'required name=search_term_string',
      },
    },
  ],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ar" dir="rtl" className="dark">
      <head>
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(orgJsonLd) }}
        />
      </head>
      <body className={`${ibmPlex.variable} ${amiri.variable} ${readexPro.variable} ${almarai.variable} font-ibm bg-nor-black text-nor-white min-h-screen flex flex-col`}>
        <Providers>
          <LiveTicker />
          <Header />
          <main className="flex-grow container mx-auto px-3 sm:px-6 lg:px-8 py-5 sm:py-8">
            {children}
          </main>
          <Footer />
        </Providers>
      </body>
    </html>
  );
}
