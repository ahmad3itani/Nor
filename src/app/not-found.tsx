import Link from 'next/link';

export default function NotFound() {
  return (
    <div className="max-w-3xl mx-auto py-20">
      <div className="bg-neutral-900 border border-neutral-800 rounded-3xl p-8 text-center space-y-4">
        <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-neutral-800 border border-neutral-700 text-neutral-300 text-sm font-readex">
          الصفحة غير موجودة
        </div>
        <h2 className="text-3xl font-bold font-readex text-white">لم نعثر على ما تبحث عنه</h2>
        <p className="text-neutral-400 font-ibm">
          ربما تغير الرابط أو لم تعد الصفحة متاحة.
        </p>
        <Link
          href="/"
          className="inline-flex px-5 py-2.5 rounded-full bg-nor-green text-black text-sm font-readex font-bold"
        >
          العودة للرئيسية
        </Link>
      </div>
    </div>
  );
}
