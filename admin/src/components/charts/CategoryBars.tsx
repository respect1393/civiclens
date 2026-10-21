import type { CategoryCount } from '../../data/selectors';

export function CategoryBars({ data }: { data: CategoryCount[] }) {
  const max = Math.max(1, ...data.map((item) => item.count));
  const total = data.reduce((sum, item) => sum + item.count, 0);

  return (
    <ul className="space-y-3.5">
      {data.map((item) => (
        <li key={item.category.id}>
          <div className="mb-1 flex items-baseline justify-between gap-3 text-sm">
            <span className="truncate font-medium text-slate-700">{item.category.label}</span>
            <span className="shrink-0 text-xs text-slate-400">
              <span className="font-semibold text-slate-900">{item.count}</span>
              {total > 0 ? ` · ${Math.round((item.count / total) * 100)}%` : ''}
            </span>
          </div>
          <div
            className="h-2 w-full overflow-hidden rounded-full bg-slate-100"
            role="img"
            aria-label={`${item.category.label}: ${item.count} reports`}
          >
            <div
              className="h-full rounded-full transition-all duration-500"
              style={{
                width: `${(item.count / max) * 100}%`,
                backgroundColor: item.category.color,
              }}
            />
          </div>
        </li>
      ))}
    </ul>
  );
}
