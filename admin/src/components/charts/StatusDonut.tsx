import type { ReportStatus } from '../../types';
import { STATUSES, STATUS_HEX } from '../../data/catalog';

const RADIUS = 52;
const STROKE = 16;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

export function StatusDonut({
  counts,
  total,
}: {
  counts: Record<ReportStatus, number>;
  total: number;
}) {
  const lengths = STATUSES.map((status) => {
    const value = counts[status] ?? 0;
    return total > 0 ? (value / total) * CIRCUMFERENCE : 0;
  });
  const segments = STATUSES.map((status, index) => ({
    status,
    value: counts[status] ?? 0,
    length: lengths[index],
    offset: -lengths.slice(0, index).reduce((sum, length) => sum + length, 0),
  }));

  return (
    <div className="flex flex-col items-center gap-5 sm:flex-row sm:items-center">
      <div className="relative shrink-0">
        <svg viewBox="0 0 140 140" width={140} height={140} role="img" aria-label="Report status distribution">
          <circle
            cx="70"
            cy="70"
            r={RADIUS}
            fill="none"
            stroke="#e2e8f0"
            strokeWidth={STROKE}
          />
          {segments
            .filter((segment) => segment.length > 0)
            .map((segment) => (
              <circle
                key={segment.status}
                cx="70"
                cy="70"
                r={RADIUS}
                fill="none"
                stroke={STATUS_HEX[segment.status]}
                strokeWidth={STROKE}
                strokeDasharray={`${segment.length} ${CIRCUMFERENCE - segment.length}`}
                strokeDashoffset={segment.offset}
                transform="rotate(-90 70 70)"
              />
            ))}
        </svg>
        <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-2xl font-bold text-slate-900">{total}</span>
          <span className="text-xs font-medium text-slate-500">reports</span>
        </div>
      </div>

      <ul className="w-full space-y-2">
        {segments.map((segment) => (
          <li key={segment.status} className="flex items-center gap-2.5 text-sm">
            <span
              className="size-2.5 shrink-0 rounded-full"
              style={{ backgroundColor: STATUS_HEX[segment.status] }}
              aria-hidden="true"
            />
            <span className="flex-1 text-slate-600">{segment.status}</span>
            <span className="font-semibold text-slate-900">{segment.value}</span>
            <span className="w-10 text-right text-xs text-slate-400">
              {total > 0 ? Math.round((segment.value / total) * 100) : 0}%
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}
