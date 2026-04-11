const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY || '';
const MODEL = process.env.OPENROUTER_MODEL || 'anthropic/claude-3.5-sonnet';

const SYSTEM_PROMPT = `
أنت محرر صحفي رياضي عربي متمرس يكتب لمنصة "نور" الإخبارية المتخصصة في كرة القدم.
مهمتك: ترجمة وإعادة صياغة الخبر التالي بأسلوب صحفي احترافي وعالي الجودة.
القواعد الخاصة بأسلوب "نور":
- استخدم العربية الفصحى الحديثة والمشوقة المناسبة للصحافة الرياضية الرقمية.
- اجعل العنوان جذاباً (Click-worthy) ولكن دون استخفاف بالمحتوى.
- أضف سياقاً بسيطاً للخبر إذا كان مفيداً للقارئ.
- لا تضف أي معلومات غير صحيحة أو من نسج الخيال.
- إذا كان الخبر مجرد تغريدة قصيرة، وسّع السياق قليلاً لجعله خبراً صغيراً (150-250 كلمة).
- حافظ على الأسماء الأجنبية بلغتها الأصلية بين أقواس أو قم بتعريبها بشكل صحيح ومشهور (مثل: كريستيانو رونالدو، ريال مدريد).
- يجب أن يكون الرد بصيغة JSON حصراً بالشكل التالي:
{
  "title": "العنوان الصحفي المثير والمختصر",
  "body": "النص الكامل للمقال مع الفقرات مقسمة بشكل جيد ومريحة للقراءة",
  "excerpt": "ملخص جذاب للخبر في جملة أو جملتين (بين 100 و160 حرفاً)",
  "tags": ["كلمة مفتاحية 1", "كلمة مفتاحية 2", "كلمة مفتاحية 3"],
  "teams": ["اسم الفريق 1", "اسم الفريق 2"],
  "category": "one of: transfers | injuries | match-report | analysis | general"
}
`;

export async function rewriteArticle(title: string, text: string, contextString?: string) {
  const content = `
العنوان الأصلي: ${title}
النص الأصلي: ${text}
${contextString ? `\nمعلومات إحصائية إضافية قد تفيدك في الصياغة: ${contextString}` : ''}
`.trim();

  try {
    const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${OPENROUTER_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: MODEL,
        response_format: { type: "json_object" },
        messages: [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user', content }
        ]
      })
    });

    if (!response.ok) {
      throw new Error(`OpenRouter Error: ${response.statusText} - ${await response.text()}`);
    }

    const data = await response.json();
    const resultText = data.choices[0].message.content;
    const resultObj = JSON.parse(resultText);

    return {
      title_ar: resultObj.title,
      body_ar: resultObj.body,
      excerpt_ar: resultObj.excerpt || null,
      tags: JSON.stringify(resultObj.tags || []),
      teams: JSON.stringify(resultObj.teams || []),
      category: resultObj.category || 'general',
    };
  } catch (error) {
    console.error('Failed to rewrite article via OpenRouter:', error);
    throw error;
  }
}

export async function generatePunditry(context: string) {
  const prompt = `أنت محلل فني وتكتيكي لكرة القدم لمنصة "نور" الإخبارية.
بناءً على معطيات المباراة التالية: ${context}
أعطني جملة تحليلية تكتيكية واحدة (بين 10 إلى 20 كلمة) باللغة العربية الفصحى الأنيقة والجذابة ذات طابع تقني. 
مثال: "التحول التكتيكي في الدقيقة 60 منح أفضلية الاستحواذ المطلق لخط الوسط، مما كسر تنظيم دفاع الخصم."
الرد يجب أن يكون الجملة فقط، بدون أي إضافات، وبدون استخدام JSON.`;

  try {
    const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${OPENROUTER_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: MODEL,
        messages: [
          { role: 'user', content: prompt }
        ]
      })
    });

    if (!response.ok) {
      throw new Error(`OpenRouter Error: ${response.statusText}`);
    }

    const data = await response.json();
    return data.choices[0].message.content.trim().replace(/^["']|["']$/g, ''); // Remove wrapping quotes if any
  } catch (error) {
    console.error('Failed to generate punditry:', error);
    return "تشهد المباراة تحركات تكتيكية مكثفة في خط الوسط سعياً لفرض السيطرة."; // Fallback graceful string
  }
}
