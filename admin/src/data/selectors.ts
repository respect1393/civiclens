import type { Category, CategoryId, Report, ReportStatus } from '../types';
import { CATEGORIES, STATUSES } from './catalog';

export interface CategoryCount {
  category: Category;
  count: number;
}

export interface DayBucket {
  date: string;
  label: string;
  count: number;
}

export interface OverviewStats {
  total: number;
  pendingReview: number;
  inProgress: number;
  resolved: number;
  open: number;
  closed: number;
  byStatus: Record<ReportStatus, number>;
  byCategory: CategoryCount[];
  submissionDays: DayBucket[];
}

export function isOpenStatus(status: ReportStatus): boolean {
  return status !== 'Resolved' && status !== 'Rejected';
}

export function sortByNewest(reports: Report[]): Report[] {
  return [...reports].sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
}

function buildSubmissionDays(reports: Report[]): DayBucket[] {
  const buckets: DayBucket[] = [];
  const formatter = new Intl.DateTimeFormat('en', { weekday: 'short' });
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  for (let index = 6; index >= 0; index -= 1) {
    const day = new Date(start.getTime() - index * 86_400_000);
    const key = day.toISOString().slice(0, 10);
    buckets.push({
      date: key,
      label: formatter.format(day),
      count: reports.filter((report) => report.submittedAt.slice(0, 10) === key).length,
    });
  }
  return buckets;
}

export function computeStats(reports: Report[]): OverviewStats {
  const byStatus = Object.fromEntries(STATUSES.map((status) => [status, 0])) as Record<
    ReportStatus,
    number
  >;
  const byCategoryId = new Map<CategoryId, number>();

  for (const report of reports) {
    byStatus[report.status] += 1;
    byCategoryId.set(report.categoryId, (byCategoryId.get(report.categoryId) ?? 0) + 1);
  }

  const byCategory = CATEGORIES.map((category) => ({
    category,
    count: byCategoryId.get(category.id) ?? 0,
  })).sort((a, b) => b.count - a.count);

  const open = reports.filter((report) => isOpenStatus(report.status)).length;

  return {
    total: reports.length,
    pendingReview: byStatus.Submitted + byStatus['Under Review'],
    inProgress: byStatus['In Progress'],
    resolved: byStatus.Resolved,
    open,
    closed: reports.length - open,
    byStatus,
    byCategory,
    submissionDays: buildSubmissionDays(reports),
  };
}

export function matchesSearch(report: Report, query: string): boolean {
  const needle = query.trim().toLowerCase();
  if (!needle) return true;
  return (
    report.id.toLowerCase().includes(needle) || report.title.toLowerCase().includes(needle)
  );
}
