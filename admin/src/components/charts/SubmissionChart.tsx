import type { DayBucket } from '../../data/selectors';

export function SubmissionChart({ buckets }: { buckets: DayBucket[] }) {
  const max = Math.max(1, ...buckets.map((bucket) => bucket.count));
  const total = buckets.reduce((sum, bucket) => sum + bucket.count, 0);

  return (
    <div>
      <div className="flex items-baseline justify-between gap-3">
        <p className="text-sm text-slate-600">
          <span className="font-bold text-slate-900">{total}</span> reports submitted in the
          last 7 days
        </p>
      </div>
      <div className="mt-4 flex h-32 items-end gap-2">
        {buckets.map((bucket) => {
          const height = bucket.count === 0 ? 4 : Math.max(12, (bucket.count / max) * 100);
          return (
            <div
              key={bucket.date}
              className="flex h-full flex-1 flex-col items-center justify-end gap-2"
            >
              <span className="text-xs font-semibold text-slate-500">
                {bucket.count > 0 ? bucket.count : ''}
              </span>
              <div
                className="w-full rounded-t bg-civic-600/85 transition-all hover:bg-civic-700"
                style={{ height: `${height}%` }}
                title={`${bucket.label}: ${bucket.count} submitted`}
                role="img"
                aria-label={`${bucket.label}: ${bucket.count} reports submitted`}
              />
            </div>
          );
        })}
      </div>
      <div className="mt-2 flex gap-2">
        {buckets.map((bucket) => (
          <span
            key={bucket.date}
            className="flex-1 text-center text-[10px] font-medium tracking-wide text-slate-400 uppercase"
          >
            {bucket.label}
          </span>
        ))}
      </div>
    </div>
  );
}
