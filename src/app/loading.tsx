export default function Loading() {
  return (
    <div className="max-w-6xl mx-auto py-16">
      <div className="space-y-4 animate-pulse">
        <div className="h-10 w-64 bg-neutral-900 rounded-2xl border border-neutral-800" />
        <div className="grid gap-4 md:grid-cols-3">
          {[1, 2, 3].map((item) => (
            <div key={item} className="h-28 bg-neutral-900 rounded-2xl border border-neutral-800" />
          ))}
        </div>
        <div className="grid gap-4 md:grid-cols-2">
          {[1, 2, 3, 4].map((item) => (
            <div key={item} className="h-40 bg-neutral-900 rounded-2xl border border-neutral-800" />
          ))}
        </div>
      </div>
    </div>
  );
}
