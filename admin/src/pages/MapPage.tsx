import { useMemo, useState } from 'react';
import { useStore } from '../data/store';
import { CATEGORIES, STATUSES, STATUS_HEX, categoryLabel, isCategoryId, isReportStatus } from '../data/catalog';
import { isOpenStatus } from '../data/selectors';
import type { Coordinates, Report } from '../types';
import { cn } from '../lib/cn';
import { relativeTime } from '../lib/format';
import { buttonGhostClass, buttonSecondaryClass } from '../lib/styles';
import { navigate } from '../router';
import {
  IconAlert,
  IconClose,
  IconInfo,
  IconMap,
  IconPin,
} from '../components/ui/Icon';
import { PageHeader } from '../components/ui/PageHeader';
import { Panel } from '../components/ui/Panel';
import { SelectField } from '../components/ui/SelectField';
import { StatusBadge } from '../components/ui/StatusBadge';

const MAP_WIDTH = 880;
const MAP_HEIGHT = 540;
const PAD_X = 56;
const PAD_Y = 48;

interface Bounds {
  minLat: number;
  maxLat: number;
  minLng: number;
  maxLng: number;
}

function computeBounds(reports: Report[]): Bounds | null {
  const points = reports
    .map((report) => report.location.coordinates)
    .filter((point): point is Coordinates => Boolean(point));
  if (points.length === 0) return null;

  const lats = points.map((point) => point.lat);
  const lngs = points.map((point) => point.lng);
  const minLatRaw = Math.min(...lats);
  const maxLatRaw = Math.max(...lats);
  const minLngRaw = Math.min(...lngs);
  const maxLngRaw = Math.max(...lngs);
  const latSpan = Math.max(maxLatRaw - minLatRaw, 0.004);
  const lngSpan = Math.max(maxLngRaw - minLngRaw, 0.004);

  return {
    minLat: minLatRaw - latSpan * 0.1,
    maxLat: maxLatRaw + latSpan * 0.1,
    minLng: minLngRaw - lngSpan * 0.1,
    maxLng: maxLngRaw + lngSpan * 0.1,
  };
}

function project(point: Coordinates, bounds: Bounds): { x: number; y: number } {
  const x =
    PAD_X +
    ((point.lng - bounds.minLng) / (bounds.maxLng - bounds.minLng)) *
      (MAP_WIDTH - 2 * PAD_X);
  const y =
    PAD_Y +
    ((bounds.maxLat - point.lat) / (bounds.maxLat - bounds.minLat)) *
      (MAP_HEIGHT - 2 * PAD_Y);
  return { x, y };
}

const ROADS = [
  'M 40 140 L 840 190',
  'M 30 360 L 850 330',
  'M 150 30 L 210 520',
  'M 640 20 L 600 520',
  'M 60 470 L 840 430',
  'M 60 60 L 840 90',
];

function MapCanvas({
  reports,
  bounds,
  selectedId,
  onSelect,
}: {
  reports: Report[];
  bounds: Bounds;
  selectedId?: string;
  onSelect: (id: string) => void;
}) {
  const points = reports
    .map((report) => {
      const coordinates = report.location.coordinates;
      if (!coordinates) return null;
      return { report, ...project(coordinates, bounds) };
    })
    .filter((entry): entry is { report: Report; x: number; y: number } => entry !== null);

  const centroids = new Map<string, { x: number; y: number; count: number }>();
  for (const point of points) {
    const existing = centroids.get(point.report.location.area);
    if (existing) {
      existing.x += point.x;
      existing.y += point.y;
      existing.count += 1;
    } else {
      centroids.set(point.report.location.area, { x: point.x, y: point.y, count: 1 });
    }
  }

  return (
    <svg
      viewBox={`0 0 ${MAP_WIDTH} ${MAP_HEIGHT}`}
      className="h-auto w-full select-none rounded-lg border border-slate-200 bg-slate-50"
      role="group"
      aria-label={`Schematic map showing ${points.length} report markers`}
    >
      <rect width={MAP_WIDTH} height={MAP_HEIGHT} fill="#f8fafc" />

      <g stroke="#e8edf3" strokeWidth="1">
        {Array.from({ length: 11 }, (_, index) => (
          <line key={`v-${index}`} x1={index * 88} y1="0" x2={index * 88} y2={MAP_HEIGHT} />
        ))}
        {Array.from({ length: 7 }, (_, index) => (
          <line key={`h-${index}`} x1="0" y1={index * 90} x2={MAP_WIDTH} y2={index * 90} />
        ))}
      </g>

      <path
        d="M 0 470 C 180 440 260 500 420 480 C 600 458 700 520 880 495 L 880 540 L 0 540 Z"
        fill="#dbeafe"
        opacity="0.75"
      />
      <rect x="520" y="210" width="150" height="96" rx="14" fill="#dcfce7" opacity="0.85" />
      <rect x="96" y="216" width="118" height="84" rx="12" fill="#dcfce7" opacity="0.7" />

      <g stroke="#e2e8f0" strokeWidth="13" fill="none" strokeLinecap="round">
        {ROADS.map((path) => (
          <path key={`casing-${path}`} d={path} />
        ))}
      </g>
      <g stroke="#ffffff" strokeWidth="9" fill="none" strokeLinecap="round">
        {ROADS.map((path) => (
          <path key={`road-${path}`} d={path} />
        ))}
      </g>

      <g stroke="#cbd5e1" strokeWidth="1.5" strokeDasharray="7 7" fill="none">
        <path d="M 300 30 C 330 160 280 320 340 520" />
        <path d="M 30 250 C 240 230 520 280 850 250" />
      </g>

      <g>
        {Array.from(centroids.entries()).map(([area, point]) => (
          <text
            key={area}
            x={point.x / point.count}
            y={point.y / point.count - 20}
            textAnchor="middle"
            fontSize="13"
            fontWeight="700"
            fill="#475569"
            stroke="#f8fafc"
            strokeWidth="4"
            paintOrder="stroke"
          >
            {area}
          </text>
        ))}
      </g>

      {points.map(({ report, x, y }) => {
        const isSelected = report.id === selectedId;
        const isOpen = isOpenStatus(report.status);
        return (
          <g
            key={report.id}
            transform={`translate(${x} ${y})`}
            role="button"
            tabIndex={0}
            aria-label={`${report.id}: ${report.title}. Status ${report.status}. ${report.location.area}.`}
            className="cursor-pointer outline-none"
            onClick={() => onSelect(report.id)}
            onKeyDown={(event) => {
              if (event.key === 'Enter' || event.key === ' ') {
                event.preventDefault();
                onSelect(report.id);
              }
            }}
          >
            <title>{`${report.id} — ${report.title} (${report.status})`}</title>
            {isSelected ? (
              <circle r="16" fill="none" stroke={STATUS_HEX[report.status]} strokeWidth="2" opacity="0.6" />
            ) : null}
            <circle
              r={isSelected ? 11 : 9}
              fill={STATUS_HEX[report.status]}
              fillOpacity="0.18"
              stroke={STATUS_HEX[report.status]}
              strokeWidth={isOpen ? 2.5 : 2}
            />
            <circle
              r={isSelected ? 5.5 : 4.5}
              fill={STATUS_HEX[report.status]}
              stroke="#ffffff"
              strokeWidth="1.5"
            />
            {isSelected ? (
              <g transform="translate(0 -34)">
                <rect
                  x="-64"
                  y="-14"
                  width="128"
                  height="28"
                  rx="6"
                  fill="#0f172a"
                  opacity="0.92"
                />
                <text
                  x="0"
                  y="5"
                  textAnchor="middle"
                  fontSize="12"
                  fontWeight="700"
                  fill="#ffffff"
                >
                  {report.id}
                </text>
              </g>
            ) : null}
          </g>
        );
      })}

      <text x="16" y={MAP_HEIGHT - 14} fontSize="12" fontWeight="700" fill="#94a3b8">
        Schematic map — markers placed from report coordinates; background is illustrative
      </text>
    </svg>
  );
}

export function MapPage({ selectedId }: { selectedId?: string }) {
  const { reports } = useStore();
  const [statusFilter, setStatusFilter] = useState('all');
  const [categoryFilter, setCategoryFilter] = useState('all');

  const bounds = useMemo(() => computeBounds(reports), [reports]);

  const filtered = useMemo(() => {
    return reports.filter((report) => {
      if (!report.location.coordinates) return false;
      if (statusFilter !== 'all' && !isReportStatus(statusFilter)) return false;
      if (statusFilter !== 'all' && report.status !== statusFilter) return false;
      if (categoryFilter !== 'all' && !isCategoryId(categoryFilter)) return false;
      if (categoryFilter !== 'all' && report.categoryId !== categoryFilter) return false;
      return true;
    });
  }, [reports, statusFilter, categoryFilter]);

  const selected = selectedId
    ? reports.find((report) => report.id === selectedId)
    : undefined;

  const hasFilters = statusFilter !== 'all' || categoryFilter !== 'all';
  const clearFilters = () => {
    setStatusFilter('all');
    setCategoryFilter('all');
  };

  const onSelect = (id: string) => navigate(`/map?sel=${encodeURIComponent(id)}`);

  if (!bounds) {
    return (
      <>
        <PageHeader
          title="Reports Map"
          description="Spatial view of reports that include coordinates."
        />
        <Panel>
          <div className="rounded-lg border border-dashed border-slate-300 bg-slate-50 p-10 text-center">
            <IconMap size={28} className="mx-auto text-slate-400" />
            <p className="mt-3 text-sm font-semibold text-slate-700">
              No report coordinates available
            </p>
            <p className="mt-1 text-sm text-slate-500">
              A map can be rendered once at least one report includes coordinates.
            </p>
          </div>
        </Panel>
      </>
    );
  }

  return (
    <>
      <PageHeader
        title="Reports Map"
        description="Explore reports by location using the coordinates submitted with each report."
        actions={
          selected ? (
            <a href={`#/reports/${selected.id}`} className={buttonSecondaryClass}>
              Open {selected.id}
            </a>
          ) : undefined
        }
      />

      <Panel bodyClassName="p-0">
        <div className="flex flex-col gap-3 border-b border-slate-200 p-4 sm:flex-row sm:items-end sm:justify-between">
          <div className="grid flex-1 grid-cols-1 gap-3 sm:grid-cols-2">
            <SelectField
              id="map-status"
              label="Status filter"
              value={statusFilter}
              onChange={setStatusFilter}
              options={[
                { value: 'all', label: 'All statuses' },
                ...STATUSES.map((status) => ({ value: status, label: status })),
              ]}
            />
            <SelectField
              id="map-category"
              label="Category filter"
              value={categoryFilter}
              onChange={setCategoryFilter}
              options={[
                { value: 'all', label: 'All categories' },
                ...CATEGORIES.map((category) => ({ value: category.id, label: category.label })),
              ]}
            />
          </div>
          <div className="flex items-center justify-between gap-3 sm:justify-end">
            <p className="text-xs text-slate-500" aria-live="polite">
              <span className="font-semibold text-slate-800">{filtered.length}</span> of{' '}
              {reports.length} markers shown
            </p>
            <button
              type="button"
              onClick={clearFilters}
              disabled={!hasFilters}
              className={cn(buttonGhostClass, 'border border-dashed border-slate-300')}
            >
              Reset filters
            </button>
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_21rem]">
          <div className="border-b border-slate-200 p-3 lg:border-r lg:border-b-0">
            {filtered.length === 0 ? (
              <div className="flex flex-col items-center justify-center gap-2 rounded-lg border border-dashed border-slate-300 bg-slate-50 px-4 py-16 text-center">
                <IconAlert size={24} className="text-slate-400" />
                <p className="text-sm font-semibold text-slate-700">No markers match</p>
                <p className="text-xs text-slate-500">
                  Adjust or reset the filters to show markers again.
                </p>
                <button type="button" onClick={clearFilters} className={buttonSecondaryClass}>
                  Reset filters
                </button>
              </div>
            ) : (
              <MapCanvas
                reports={filtered}
                bounds={bounds}
                selectedId={selectedId}
                onSelect={onSelect}
              />
            )}

            <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-2">
              {STATUSES.map((status) => (
                <span key={status} className="inline-flex items-center gap-1.5 text-xs text-slate-600">
                  <span
                    className="size-2.5 rounded-full"
                    style={{ backgroundColor: STATUS_HEX[status] }}
                    aria-hidden="true"
                  />
                  {status}
                </span>
              ))}
            </div>
          </div>

          <aside className="max-h-[34rem] overflow-y-auto p-4" aria-label="Map report list">
            {selected ? (
              <div className="mb-4 rounded-lg border border-civic-200 bg-civic-50/60 p-3">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <p className="font-mono text-xs font-semibold text-civic-800">
                      {selected.id}
                    </p>
                    <p className="mt-0.5 text-sm leading-snug font-semibold text-slate-900">
                      {selected.title}
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() => navigate('/map')}
                    className="rounded-lg p-1 text-slate-400 transition hover:bg-white hover:text-slate-700"
                  >
                    <IconClose size={16} />
                    <span className="sr-only">Clear selection</span>
                  </button>
                </div>
                <div className="mt-2 flex flex-wrap items-center gap-2">
                  <StatusBadge status={selected.status} size="sm" />
                  <span className="text-xs text-slate-500">
                    {categoryLabel(selected.categoryId)}
                  </span>
                </div>
                <p className="mt-2 flex items-start gap-1.5 text-xs text-slate-600">
                  <IconPin size={14} className="mt-0.5 shrink-0 text-slate-400" />
                  <span>
                    {selected.location.address}, {selected.location.area}
                  </span>
                </p>
                <p className="mt-1 text-xs text-slate-400">Updated {relativeTime(selected.updatedAt)}</p>
                <div className="mt-3 flex flex-wrap gap-2">
                  <a href={`#/reports/${selected.id}`} className={buttonSecondaryClass}>
                    Open full report
                  </a>
                  <button
                    type="button"
                    onClick={() => navigate('/map')}
                    className={buttonGhostClass}
                  >
                    Clear
                  </button>
                </div>
              </div>
            ) : (
              <div className="mb-4 rounded-lg bg-slate-50 p-3 text-xs leading-relaxed text-slate-500">
                Select a marker or a list item to preview a report. Use the keyboard: markers and
                list items are focusable with Tab, and activate with Enter.
              </div>
            )}

            <p className="mb-2 text-[11px] font-bold tracking-wider text-slate-400 uppercase">
              Markers in view
            </p>
            <ul className="space-y-1.5">
              {filtered.map((report) => (
                <li key={report.id}>
                  <button
                    type="button"
                    onClick={() => onSelect(report.id)}
                    aria-pressed={report.id === selectedId}
                    className={cn(
                      'w-full rounded-lg border px-2.5 py-2 text-left transition',
                      report.id === selectedId
                        ? 'border-civic-300 bg-civic-50'
                        : 'border-transparent hover:border-slate-200 hover:bg-slate-50',
                    )}
                  >
                    <span className="flex items-center gap-2">
                      <span
                        className="size-2.5 shrink-0 rounded-full"
                        style={{ backgroundColor: STATUS_HEX[report.status] }}
                        aria-hidden="true"
                      />
                      <span className="font-mono text-xs font-semibold text-slate-500">
                        {report.id}
                      </span>
                      <span className="ml-auto text-xs text-slate-400">
                        {report.location.area}
                      </span>
                    </span>
                    <span className="mt-0.5 block truncate text-xs font-medium text-slate-800">
                      {report.title}
                    </span>
                  </button>
                </li>
              ))}
              {filtered.length === 0 ? (
                <li className="rounded-lg bg-slate-50 px-3 py-4 text-center text-xs text-slate-500">
                  No markers match the current filters.
                </li>
              ) : null}
            </ul>
          </aside>
        </div>
      </Panel>

      <Panel
        className="mt-5"
        title="About this map"
        description="How this view is drawn"
        action={<IconInfo size={16} className="text-slate-400" />}
      >
        <div className="grid grid-cols-1 gap-5 md:grid-cols-2">
          <div>
            <p className="mb-2 text-[11px] font-bold tracking-wider text-emerald-700 uppercase">
              Implemented
            </p>
            <ul className="space-y-2 text-sm leading-relaxed text-slate-600">
              <li>
                A schematic map drawn with SVG, so no extra map library or network access is
                required.
              </li>
              <li>
                Markers positioned from the coordinates stored with each report, with
                keyboard-focusable markers and an equivalent report list.
              </li>
              <li>Status and category filtering, marker selection and links to full reports.</li>
            </ul>
          </div>
          <div>
            <p className="mb-2 text-[11px] font-bold tracking-wider text-amber-700 uppercase">
              Remaining for a later phase
            </p>
            <ul className="space-y-2 text-sm leading-relaxed text-slate-600">
              <li>
                A real slippy map with geographic tiles (for example Leaflet or MapLibre plus a
                tile provider) — it needs an additional dependency and network access that this
                phase avoids.
              </li>
              <li>Geocoding and marker clustering.</li>
              <li>
                Geographically accurate rendering: the background is decorative and does not
                correspond to real streets or boundaries.
              </li>
            </ul>
          </div>
        </div>
        <p className="mt-4 rounded-lg bg-slate-50 px-3 py-2.5 text-xs leading-relaxed text-slate-600">
          The background roads and shading are illustrative and not tied to real geography. Marker
          positions are derived from the coordinates stored with each report.
        </p>
      </Panel>
    </>
  );
}
