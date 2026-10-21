import type { ReportStatus } from '../../types';
import { cn } from '../../lib/cn';

const STATUS_CLASSES: Record<ReportStatus, string> = {
  Submitted: 'bg-slate-100 text-slate-700 ring-slate-200',
  'Under Review': 'bg-amber-50 text-amber-800 ring-amber-200',
  'In Progress': 'bg-civic-50 text-civic-800 ring-civic-200',
  Resolved: 'bg-emerald-50 text-emerald-800 ring-emerald-200',
  Rejected: 'bg-rose-50 text-rose-800 ring-rose-200',
};

export function StatusBadge({
  status,
  size = 'md',
}: {
  status: ReportStatus;
  size?: 'sm' | 'md';
}) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 rounded-full font-medium whitespace-nowrap ring-1 ring-inset',
        size === 'sm' ? 'px-2 py-0.5 text-[11px]' : 'px-2.5 py-1 text-xs',
        STATUS_CLASSES[status],
      )}
    >
      <span className="size-1.5 rounded-full bg-current" aria-hidden="true" />
      {status}
    </span>
  );
}
