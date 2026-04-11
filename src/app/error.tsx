"use client";

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <div className="max-w-3xl mx-auto py-20">
      <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-8 text-center space-y-4">
        <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-red-500/10 border border-red-500/20 text-red-400 text-sm font-readex">
          حدث خطأ غير متوقع
        </div>
        <h2 className="text-3xl font-bold font-readex text-white">تعذر إكمال هذه الصفحة</h2>
        <p className="text-neutral-400 font-ibm">
          حاول إعادة المحاولة. إذا استمر الخطأ، حدّث الصفحة أو ارجع للرئيسية.
        </p>
        {error?.message ? (
          <p className="text-xs text-neutral-600 font-ibm break-words">{error.message}</p>
        ) : null}
        <div className="flex items-center justify-center gap-3">
          <button
            onClick={reset}
            className="px-5 py-2.5 rounded-full bg-nor-green text-black text-sm font-readex font-bold"
          >
            إعادة المحاولة
          </button>
          <a
            href="/"
            className="px-5 py-2.5 rounded-full border border-neutral-700 text-sm font-readex text-neutral-300 hover:text-white hover:border-neutral-500 transition-colors"
          >
            العودة للرئيسية
          </a>
        </div>
      </div>
    </div>
  );
}
