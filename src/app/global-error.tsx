"use client";

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <html lang="ar" dir="rtl" className="dark">
      <body className="bg-nor-black text-nor-white min-h-screen">
        <div className="max-w-3xl mx-auto py-20 px-6">
          <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-8 text-center space-y-4">
            <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-red-500/10 border border-red-500/20 text-red-400 text-sm font-readex">
              خطأ عام في التطبيق
            </div>
            <h2 className="text-3xl font-bold font-readex text-white">حدث خلل أثناء تحميل التطبيق</h2>
            <p className="text-neutral-400 font-ibm">
              يمكنك إعادة المحاولة أو تحديث الصفحة.
            </p>
            {error?.message ? (
              <p className="text-xs text-neutral-600 font-ibm break-words">{error.message}</p>
            ) : null}
            <button
              onClick={reset}
              className="px-5 py-2.5 rounded-full bg-nor-green text-black text-sm font-readex font-bold"
            >
              إعادة المحاولة
            </button>
          </div>
        </div>
      </body>
    </html>
  );
}
