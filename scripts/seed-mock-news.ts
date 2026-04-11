import { db } from '../src/lib/db';

const mockArticles = [
  {
    slug: 'real-madrid-champions-league-2024',
    title_ar: 'ريال مدريد يقلب الطاولة على باريس سان جيرمان ويحجز مقعده في نصف النهائي',
    body_ar: 'في مباراة تحتبس لها الأنفاس، تمكن نادي ريال مدريد الإسباني من تحقيق ريمونتادا تاريخية جديدة في دوري أبطال أوروبا، متغلباً على ضيفه باريس سان جيرمان الفرنسي بنتيجة 3-1.\n\nتألق النجم البرازيلي فينيسيوس جونيور مسجلاً هدفين حاسمين، بينما أضاف الإنجليزي جود بيلينجهام الهدف الثالث ليؤكد تفوق الملكي أوروبياً. ورغم سيطرة الفريق الباريسي في الشوط الأول، إلا أن خبرة ريال مدريد لعبت دوراً حاسماً في الدقائق الأخيرة.',
    source: 'Sky Sports',
    source_url: 'https://skysports.com/football',
    tags: JSON.stringify(['ريال_مدريد', 'دوري_أبطال_أوروبا', 'باريس_سان_جيرمان'])
  },
  {
    slug: 'liverpool-premier-league-lead',
    title_ar: 'ليفربول ينفرد بصدارة الدوري الإنجليزي بعد تعثر مانشستر سيتي أمام أرسنال',
    body_ar: 'استغل ليفربول تعادل منافسيه المباشرين ليعتلي صدارة ترتيب الدوري الإنجليزي الممتاز بعد فوز مستحق على برايتون بهدفين دون رد في الأنفيلد.\n\nشهدت الجولة تعادلاً سلبياً مخيباً للآمال بين مانشستر سيتي وأرسنال في ملعب الاتحاد، مما أتاح لكتيبة الريدز اقتناص المركز الأول.',
    source: 'BBC Sport',
    source_url: 'https://bbc.com/sport/football',
    tags: JSON.stringify(['ليفربول', 'الدوري_الإنجليزي', 'مانشستر_سيتي'])
  },
  {
    slug: 'saudi-pro-league-ronaldo-hattrick',
    title_ar: 'كريستيانو رونالدو يسجل "هاتريك" جديد ويقود النصر لانتصار كاسح',
    body_ar: 'في ليلة كروية ساحرة في دوري روشن السعودي، أثبت الأسطورة البرتغالية كريستيانو رونالدو مجدداً أنه لا يزال في قمة عطائه بتسجيله ثلاثة أهداف ليقود فريقه النصر لفوز عريض بنتيجة 4-0.',
    source: 'Sky Sports',
    source_url: 'https://skysports.com/football',
    tags: JSON.stringify(['كريستيانو_رونالدو', 'النصر', 'دوري_روشن'])
  }
];

async function main() {
  console.log('Seeding mock news into the database...');
  for (const article of mockArticles) {
    await db.execute({
      sql: `INSERT OR REPLACE INTO articles (slug, title_ar, body_ar, source, source_url, tags)
            VALUES (?, ?, ?, ?, ?, ?)`,
      args: [article.slug, article.title_ar, article.body_ar, article.source, article.source_url, article.tags],
    });
  }
  console.log('Successfully inserted mock articles!');
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
