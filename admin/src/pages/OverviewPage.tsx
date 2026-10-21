import { useMemo } from 'react';
import { useStore } from '../data/store';
import { computeStats, sortByNewest } from '../data/selectors';
import { relativeTime } from '../lib/format';
import { buttonSecondaryClass } from '../lib/styles';
import { ActivityFeed } from '../components/activity/ActivityFeed';
import { CategoryBars } from '../components/charts/CategoryBars';
import { StatusDonut } from '../components/charts/StatusDonut';
import { SubmissionChart } from '../components/charts/SubmissionChart';
import { ReportsTable } from '../components/reports/ReportsTable';
import {
  IconCheckCircle,
  IconClock,
  IconLayers,
  IconRefresh,
} from '../components/ui/Icon';
import { PageHeader } from '../components/ui/PageHeader';
import { Panel } from '../components/ui/Panel';
import { StatCard } from '../components/ui/StatCard';

export function OverviewPage() {
  const { reports, activity, preferences } = useStore();
  const stats = useMemo(() => computeStats(reports), [reports]);
  const recent = useMemo(() => sortByNewest(reports).slice(0, 6), [reports]);
  const recentActivity = useMemo(
    () => [...activity].sort((a, b) => b.at.localeCompare(a.at)).slice(0, 7),
    [activity],
  );
  const latestUpdate = recent[0];

  const openPercent = stats.total > 0 ? Math.round((stats.open / stats.total) * 100) : 0;

  return (
    <>
      <PageHeader
        title="Overview"
        description="Current workload and report statistics across every report submitted to CivicLens."
        actions={
          <a href="#/reports" className={buttonSecondaryClass}>
            View all reports
          </a>
        }
      />

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Total Reports"
          value={stats.total}
          hint="Every report returned by the backend."
          icon={<IconLayers size={20} />}
          accent="civic"
          meta={
            <span className="text-xs font-medium text-slate-400">
              {stats.open} open · {stats.closed} closed
            </span>
          }
        />
        <StatCard
          label="Submitted / Pending Review"
          value={stats.pendingReview}
          hint="Submitted or under review, awaiting an administrative decision."
          icon={<IconClock size={20} />}
          accent="amber"
          meta={
            <span className="text-xs font-medium text-slate-400">
              {stats.byStatus.Submitted} submitted · {stats.byStatus['Under Review']} in review
            </span>
          }
        />
        <StatCard
          label="In Progress"
          value={stats.inProgress}
          hint="Reports currently being worked on."
          icon={<IconRefresh size={20} />}
          accent="violet"
          meta={
            <span className="text-xs font-medium text-slate-400">
              {openPercent}% of all reports are still open
            </span>
          }
        />
        <StatCard
          label="Resolved"
          value={stats.resolved}
          hint="Reports closed after work was completed."
          icon={<IconCheckCircle size={20} />}
          accent="emerald"
          meta={
            <span className="text-xs font-medium text-slate-400">
              {stats.byStatus.Rejected} rejected · {stats.total} total
            </span>
          }
        />
      </div>

      <div className="mt-5 grid grid-cols-1 gap-5 lg:grid-cols-3">
        <Panel
          title="Report status distribution"
          description="Share of reports in each status"
        >
          <StatusDonut counts={stats.byStatus} total={stats.total} />
        </Panel>

        <Panel title="Reports by category" description="Where reports are concentrated">
          <CategoryBars data={stats.byCategory} />
        </Panel>

        <Panel
          title="Recent administrative activity"
          description="Latest status changes and notes"
          action={
            <a
              href="#/activity"
              className="text-xs font-semibold text-civic-700 hover:underline"
            >
              View all
            </a>
          }
          bodyClassName="p-4 sm:p-5"
        >
          <ActivityFeed activity={recentActivity} limit={7} />
        </Panel>
      </div>

      <div className="mt-5 grid grid-cols-1 gap-5 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <Panel
            title="Recent reports"
            description={
              latestUpdate
                ? `Most recently updated: ${latestUpdate.id} · ${relativeTime(latestUpdate.updatedAt)}`
                : 'No reports to summarise'
            }
            action={
              <a
                href="#/reports"
                className="text-xs font-semibold text-civic-700 hover:underline"
              >
                Manage reports
              </a>
            }
            bodyClassName="p-0"
          >
            <ReportsTable
              reports={recent}
              density={preferences.density}
              variant="flush"
              emptyTitle="No reports yet"
              emptyDescription="The backend has not returned any reports."
            />
          </Panel>
        </div>

        <Panel
          title="Report workload"
          description="Open versus closed reports"
        >
          <div className="mb-5">
            <div className="mb-2 flex items-baseline justify-between text-sm">
              <span className="text-slate-600">
                <span className="font-bold text-slate-900">{stats.open}</span> open
              </span>
              <span className="text-slate-600">
                <span className="font-bold text-slate-900">{stats.closed}</span> closed
              </span>
            </div>
            <div
              className="flex h-2.5 w-full overflow-hidden rounded-full bg-slate-100"
              role="img"
              aria-label={`${stats.open} open and ${stats.closed} closed reports`}
            >
              <div className="h-full bg-civic-600" style={{ width: `${openPercent}%` }} />
              <div className="h-full bg-emerald-500" style={{ width: `${100 - openPercent}%` }} />
            </div>
            <p className="mt-2 text-xs text-slate-500">
              Open includes {stats.pendingReview} pending review and {stats.inProgress} in
              progress.
            </p>
          </div>

          <div className="border-t border-slate-100 pt-4">
            <SubmissionChart buckets={stats.submissionDays} />
          </div>

          <div className="mt-5 border-t border-slate-100 pt-4">
            <p className="mb-2 text-[11px] font-bold tracking-wider text-slate-400 uppercase">
              Busiest categories
            </p>
            <ul className="space-y-1.5">
              {stats.byCategory.slice(0, 3).map((item) => (
                <li
                  key={item.category.id}
                  className="flex items-center justify-between gap-2 text-sm"
                >
                  <span className="inline-flex min-w-0 items-center gap-2 text-slate-600">
                    <span
                      className="size-2 shrink-0 rounded-full"
                      style={{ backgroundColor: item.category.color }}
                      aria-hidden="true"
                    />
                    <span className="truncate">{item.category.label}</span>
                  </span>
                  <span className="font-semibold text-slate-900">{item.count}</span>
                </li>
              ))}
            </ul>          </div>
        </Panel>
      </div>
    </>
  );
}
