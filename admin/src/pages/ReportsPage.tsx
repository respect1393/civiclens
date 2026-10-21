import { useMemo, useState } from 'react';
import type { Report } from '../types';
import { useStore } from '../data/store';
import { matchesSearch } from '../data/selectors';
import { CATEGORIES, STATUSES, isCategoryId, isReportStatus } from '../data/catalog';
import { cn } from '../lib/cn';
import { buttonGhostClass, buttonSecondaryClass, inputClass } from '../lib/styles';
import { ReportsTable } from '../components/reports/ReportsTable';
import { IconFilter, IconSearch } from '../components/ui/Icon';
import { PageHeader } from '../components/ui/PageHeader';
import { Panel } from '../components/ui/Panel';
import { SelectField } from '../components/ui/SelectField';

type SortKey = 'updated' | 'newest' | 'oldest' | 'title' | 'status';

const SORT_OPTIONS = [
  { value: 'updated', label: 'Last updated' },
  { value: 'newest', label: 'Newest first' },
  { value: 'oldest', label: 'Oldest first' },
  { value: 'title', label: 'Title A to Z' },
  { value: 'status', label: 'Status' },
];

const STATUS_ORDER = new Map(STATUSES.map((status, index) => [status, index]));

function sortReports(reports: Report[], key: SortKey) {
  const list = [...reports];
  switch (key) {
    case 'newest':
      return list.sort((a, b) => b.submittedAt.localeCompare(a.submittedAt));
    case 'oldest':
      return list.sort((a, b) => a.submittedAt.localeCompare(b.submittedAt));
    case 'title':
      return list.sort((a, b) => a.title.localeCompare(b.title));
    case 'status':
      return list.sort((a, b) => {
        const diff =
          (STATUS_ORDER.get(a.status) ?? 0) - (STATUS_ORDER.get(b.status) ?? 0);
        return diff !== 0 ? diff : a.id.localeCompare(b.id);
      });
    default:
      return list.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  }
}

export function ReportsPage() {
  const { reports, preferences } = useStore();
  const [query, setQuery] = useState('');
  const [category, setCategory] = useState('all');
  const [status, setStatus] = useState('all');
  const [sort, setSort] = useState<SortKey>('updated');

  const hasFilters = query.trim() !== '' || category !== 'all' || status !== 'all';

  const filtered = useMemo(() => {
    const matched = reports.filter((report) => {
      if (!matchesSearch(report, query)) return false;
      if (category !== 'all' && !isCategoryId(category)) return false;
      if (category !== 'all' && report.categoryId !== category) return false;
      if (status !== 'all' && !isReportStatus(status)) return false;
      if (status !== 'all' && report.status !== status) return false;
      return true;
    });
    return sortReports(matched, sort);
  }, [reports, query, category, status, sort]);

  const clearFilters = () => {
    setQuery('');
    setCategory('all');
    setStatus('all');
  };

  return (
    <>
      <PageHeader
        title="Reports"
        description="Search, filter and review every report submitted through CivicLens."
      />

      <Panel bodyClassName="p-4 sm:p-5">
        <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-[minmax(0,2fr)_repeat(3,minmax(0,1fr))_auto]">
          <div>
            <label htmlFor="report-search" className="mb-1.5 block text-xs font-semibold tracking-wide text-slate-700">
              Search
            </label>
            <div className="relative">
              <IconSearch
                size={16}
                className="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-slate-400"
              />
              <input
                id="report-search"
                type="search"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Search by report title or ID…"
                className={cn(inputClass, 'pl-9')}
              />
            </div>
          </div>

          <SelectField
            id="report-category"
            label="Category"
            value={category}
            onChange={setCategory}
            options={[
              { value: 'all', label: 'All categories' },
              ...CATEGORIES.map((item) => ({ value: item.id, label: item.label })),
            ]}
          />

          <SelectField
            id="report-status"
            label="Status"
            value={status}
            onChange={setStatus}
            options={[
              { value: 'all', label: 'All statuses' },
              ...STATUSES.map((item) => ({ value: item, label: item })),
            ]}
          />

          <SelectField
            id="report-sort"
            label="Sort by"
            value={sort}
            onChange={(value) => setSort(value as SortKey)}
            options={SORT_OPTIONS}
          />

          <div className="flex items-end">
            <button
              type="button"
              onClick={clearFilters}
              disabled={!hasFilters}
              className={cn(buttonGhostClass, 'w-full border border-dashed border-slate-300')}
            >
              Clear filters
            </button>
          </div>
        </div>

        <div className="mt-4 flex flex-wrap items-center justify-between gap-2 border-t border-slate-100 pt-3 text-xs text-slate-500">
          <p aria-live="polite">
            Showing <span className="font-semibold text-slate-800">{filtered.length}</span> of{' '}
            <span className="font-semibold text-slate-800">{reports.length}</span> reports
          </p>
          <p className="inline-flex items-center gap-1.5">
            <IconFilter size={14} className="text-slate-400" />
            {hasFilters ? 'Filters active' : 'No filters applied'}
          </p>
        </div>
      </Panel>

      <div className="mt-5">
        <ReportsTable
          reports={filtered}
          density={preferences.density}
          emptyTitle="No reports match your filters"
          emptyDescription="No report matches the current search, category and status combination."
          emptyAction={
            hasFilters ? (
              <button type="button" onClick={clearFilters} className={buttonSecondaryClass}>
                Clear filters
              </button>
            ) : undefined
          }
        />
      </div>
    </>
  );
}
