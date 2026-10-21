import type { ReactNode } from 'react';
import type { Report, TableDensity } from '../../types';
import { categoryLabel } from '../../data/catalog';
import { cn } from '../../lib/cn';
import { formatDateTime, relativeTime } from '../../lib/format';
import { EmptyState } from '../ui/EmptyState';
import { IconChevronRight, IconPin } from '../ui/Icon';
import { StatusBadge } from '../ui/StatusBadge';

function PriorityTag({ priority }: { priority: Report['priority'] }) {
  if (priority !== 'High') return null;
  return (
    <span className="ml-2 inline-flex items-center rounded border border-rose-200 bg-rose-50 px-1.5 py-px text-[10px] font-bold tracking-wide text-rose-700 uppercase">
      High priority
    </span>
  );
}

export function ReportsTable({
  reports,
  density = 'comfortable',
  variant = 'card',
  emptyTitle = 'No reports found',
  emptyDescription = 'Try adjusting the search or filters.',
  emptyAction,
  footer,
}: {
  reports: Report[];
  density?: TableDensity;
  variant?: 'card' | 'flush';
  emptyTitle?: string;
  emptyDescription?: string;
  emptyAction?: ReactNode;
  footer?: ReactNode;
}) {
  const shellClass =
    variant === 'flush'
      ? 'overflow-hidden rounded-b-xl'
      : 'overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm';

  if (reports.length === 0) {
    return (
      <div className={variant === 'flush' ? 'bg-white' : shellClass}>
        <EmptyState title={emptyTitle} description={emptyDescription} action={emptyAction} />
      </div>
    );
  }

  const rowPadding = density === 'compact' ? 'py-2' : 'py-3.5';

  return (
    <div className={shellClass}>
      <div className="relative hidden overflow-x-auto md:block">
        <table className="min-w-full border-collapse text-left text-sm">
          <thead>
            <tr className="border-b border-slate-200 bg-slate-50/80 text-[11px] tracking-wider text-slate-500 uppercase">
              <th scope="col" className="px-4 py-2.5 font-semibold">
                Report
              </th>
              <th scope="col" className="px-4 py-2.5 font-semibold">
                Category
              </th>
              <th scope="col" className="px-4 py-2.5 font-semibold">
                Location
              </th>
              <th scope="col" className="px-4 py-2.5 font-semibold">
                Status
              </th>
              <th scope="col" className="px-4 py-2.5 font-semibold">
                Updated
              </th>
              <th scope="col" className="px-4 py-2.5 text-right font-semibold">
                <span className="sr-only">Open</span>
              </th>
            </tr>
          </thead>
          <tbody>
            {reports.map((report) => (
              <tr
                key={report.id}
                className={cn(
                  'border-b border-slate-100 transition last:border-0 hover:bg-slate-50/70',
                  rowPadding,
                )}
              >
                <td className="max-w-md px-4 align-middle">
                  <a
                    href={`#/reports/${report.id}`}
                    className="block rounded text-sm font-semibold text-slate-900 transition hover:text-civic-700"
                  >
                    <span className="font-mono text-xs font-medium text-slate-400">
                      {report.id}
                    </span>
                    <span className="block truncate">
                      {report.title}
                      <PriorityTag priority={report.priority} />
                    </span>
                  </a>
                </td>
                <td className="px-4 align-middle text-slate-600">
                  {categoryLabel(report.categoryId)}
                </td>
                <td className="px-4 align-middle text-slate-600">
                  <span className="block truncate">{report.location.area}</span>
                  <span className="block text-xs text-slate-400">
                    {report.location.address}
                  </span>
                </td>
                <td className="px-4 align-middle">
                  <StatusBadge status={report.status} size="sm" />
                </td>
                <td className="px-4 align-middle whitespace-nowrap text-slate-500">
                  <span title={formatDateTime(report.updatedAt)}>
                    {relativeTime(report.updatedAt)}
                  </span>
                </td>
                <td className="px-4 text-right align-middle">
                  <a
                    href={`#/reports/${report.id}`}
                    aria-label={`Open report ${report.id}`}
                    className="inline-flex rounded-lg p-1.5 text-slate-400 transition hover:bg-slate-100 hover:text-civic-700"
                  >
                    <IconChevronRight size={17} />
                  </a>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <ul className="divide-y divide-slate-100 md:hidden">
        {reports.map((report) => (
          <li key={report.id}>
            <a
              href={`#/reports/${report.id}`}
              className="block px-4 py-3.5 transition hover:bg-slate-50"
            >
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="font-mono text-xs font-medium text-slate-400">{report.id}</p>
                  <p className="mt-0.5 text-sm leading-snug font-semibold text-slate-900">
                    {report.title}
                    <PriorityTag priority={report.priority} />
                  </p>
                </div>
                <StatusBadge status={report.status} size="sm" />
              </div>
              <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-slate-500">
                <span>{categoryLabel(report.categoryId)}</span>
                <span className="inline-flex items-center gap-1">
                  <IconPin size={13} className="text-slate-400" />
                  {report.location.area}
                </span>
                <span>{relativeTime(report.updatedAt)}</span>
              </div>
            </a>
          </li>
        ))}
      </ul>

      {footer ? (
        <div className="border-t border-slate-100 bg-slate-50/60 px-4 py-3">{footer}</div>
      ) : null}
    </div>
  );
}
