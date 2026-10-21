import type { ActivityItem } from '../../types';
import { dayLabel, relativeTime } from '../../lib/format';
import { EmptyState } from '../ui/EmptyState';
import { IconInfo, IconNote, IconRefresh } from '../ui/Icon';

const TYPE_META: Record<
  ActivityItem['type'],
  { label: string; className: string; Icon: typeof IconInfo }
> = {
  status: { label: 'Status change', className: 'bg-civic-50 text-civic-700', Icon: IconRefresh },
  note: { label: 'Note added', className: 'bg-amber-50 text-amber-700', Icon: IconNote },
  system: { label: 'System', className: 'bg-slate-100 text-slate-500', Icon: IconInfo },
};

interface Group {
  label: string;
  items: ActivityItem[];
}

function groupByDay(items: ActivityItem[]): Group[] {
  const groups: Group[] = [];
  for (const item of items) {
    const label = dayLabel(item.at);
    const existing = groups.find((group) => group.label === label);
    if (existing) {
      existing.items.push(item);
    } else {
      groups.push({ label, items: [item] });
    }
  }
  return groups;
}

export function ActivityFeed({
  activity,
  limit,
  emptyTitle = 'No activity yet',
  emptyDescription = 'Administrative actions on reports will appear here.',
}: {
  activity: ActivityItem[];
  limit?: number;
  emptyTitle?: string;
  emptyDescription?: string;
}) {
  const ordered = [...activity].sort((a, b) => b.at.localeCompare(a.at));
  const visible = typeof limit === 'number' ? ordered.slice(0, limit) : ordered;

  if (visible.length === 0) {
    return <EmptyState title={emptyTitle} description={emptyDescription} />;
  }

  return (
    <div className="space-y-5">
      {groupByDay(visible).map((group) => (
        <div key={group.label}>
          <p className="mb-2 text-[11px] font-bold tracking-wider text-slate-400 uppercase">
            {group.label}
          </p>
          <ol className="space-y-2">
            {group.items.map((item) => {
              const meta = TYPE_META[item.type];
              const Icon = meta.Icon;
              return (
                <li key={item.id} className="flex items-start gap-3">
                  <span
                    className={`mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full ${meta.className}`}
                    title={meta.label}
                  >
                    <Icon size={15} />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="text-sm leading-snug text-slate-700">
                      {item.actor ? (
                        <>
                          <span className="font-semibold text-slate-900">{item.actor}</span>{' '}
                        </>
                      ) : null}
                      {item.message}
                    </p>
                    <p className="mt-0.5 flex flex-wrap items-center gap-x-2 text-xs text-slate-400">
                      <span>{relativeTime(item.at)}</span>
                      {item.reportId ? (
                        <a
                          href={`#/reports/${item.reportId}`}
                          className="font-medium text-civic-700 hover:underline"
                        >
                          Open {item.reportId}
                        </a>
                      ) : null}
                    </p>
                  </div>
                </li>
              );
            })}
          </ol>
        </div>
      ))}
    </div>
  );
}
