export function LoadingState({ rows = 5, label = 'Loading' }: { rows?: number; label?: string }) {
  return (
    <div
      className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5"
      role="status"
      aria-live="polite"
    >
      <span className="sr-only">{label}</span>
      <div className="mb-4 h-4 w-40 animate-pulse rounded bg-slate-200" aria-hidden="true" />
      <ul className="space-y-3" aria-hidden="true">
        {Array.from({ length: rows }, (_, index) => (
          <li key={index} className="flex items-center gap-4">
            <div className="h-9 w-9 shrink-0 animate-pulse rounded-lg bg-slate-200" />
            <div className="flex-1 space-y-2">
              <div
                className="h-3 animate-pulse rounded bg-slate-200"
                style={{ width: `${55 + ((index * 13) % 35)}%` }}
              />
              <div className="h-3 w-1/4 animate-pulse rounded bg-slate-100" />
            </div>
            <div className="hidden h-5 w-20 animate-pulse rounded-full bg-slate-200 sm:block" />
          </li>
        ))}
      </ul>
    </div>
  );
}
