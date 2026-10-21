import type {
  AdminNote,
  CategoryId,
  Report,
  ReportStatus,
  StatusHistoryEntry,
} from '../types';
import { isCategoryId } from '../data/catalog';
import { apiFetch, apiFetchBlob } from './client';

interface BackendUser {
  id: string;
  name: string;
  email: string;
}

interface BackendStatusHistory {
  id: string;
  reportId: string;
  oldStatus: string | null;
  newStatus: string;
  changedAt: string;
}

interface BackendAdminNote {
  id: string;
  reportId: string;
  adminId: string;
  content: string;
  createdAt: string;
  admin?: BackendUser;
}

interface BackendReport {
  id: string;
  title: string;
  description: string;
  category: string;
  status: string;
  area: string;
  address: string;
  landmark: string | null;
  latitude: number | null;
  longitude: number | null;
  photoPath: string | null;
  userId: string;
  state: string | null;
  district: string | null;
  createdAt: string;
  updatedAt: string;
  user?: BackendUser;
  statusHistory?: BackendStatusHistory[];
  adminNotes?: BackendAdminNote[];
}

interface BackendPagination {
  page: number;
  limit: number;
  total: number;
  totalPages: number;
}

interface BackendListResponse {
  data: BackendReport[];
  pagination: BackendPagination;
}

const STATUS_TO_PRESENTATION: Record<string, ReportStatus> = {
  SUBMITTED: 'Submitted',
  UNDER_REVIEW: 'Under Review',
  IN_PROGRESS: 'In Progress',
  RESOLVED: 'Resolved',
  REJECTED: 'Rejected',
};

const STATUS_TO_BACKEND: Record<ReportStatus, string> = {
  Submitted: 'SUBMITTED',
  'Under Review': 'UNDER_REVIEW',
  'In Progress': 'IN_PROGRESS',
  Resolved: 'RESOLVED',
  Rejected: 'REJECTED',
};

const CATEGORY_TO_PRESENTATION: Record<string, CategoryId> = {
  ROADS: 'roads',
  STREETLIGHTS: 'streetlights',
  WATER: 'water',
  WASTE: 'waste',
  DRAINAGE: 'drainage',
  SAFETY: 'safety',
};

function toStatus(value: string | null | undefined): ReportStatus {
  return STATUS_TO_PRESENTATION[value ?? ''] ?? 'Submitted';
}

function toCategory(value: string): CategoryId {
  const mapped = CATEGORY_TO_PRESENTATION[value];
  return mapped && isCategoryId(mapped) ? mapped : 'safety';
}

function mapHistory(entries: BackendStatusHistory[] | undefined): StatusHistoryEntry[] {
  return (entries ?? []).map((entry) => ({
    id: entry.id,
    status: toStatus(entry.newStatus),
    previousStatus: entry.oldStatus ? toStatus(entry.oldStatus) : undefined,
    changedAt: entry.changedAt,
    // The backend stores no actor for a transition; it is left absent on purpose.
  }));
}

function mapNotes(notes: BackendAdminNote[] | undefined): AdminNote[] {
  return (notes ?? []).map((note) => ({
    id: note.id,
    body: note.content,
    author: note.admin?.name ?? 'Unknown administrator',
    createdAt: note.createdAt,
  }));
}

function mapReport(raw: BackendReport): Report {
  const hasCoordinates =
    typeof raw.latitude === 'number' && typeof raw.longitude === 'number';

  return {
    id: raw.id,
    title: raw.title,
    description: raw.description,
    categoryId: toCategory(raw.category),
    status: toStatus(raw.status),
    submittedAt: raw.createdAt,
    updatedAt: raw.updatedAt,
    reporterName: raw.user?.name,
    reporterEmail: raw.user?.email,
    location: {
      area: raw.area,
      address: raw.address,
      landmark: raw.landmark ?? undefined,
      coordinates: hasCoordinates
        ? { lat: raw.latitude as number, lng: raw.longitude as number }
        : undefined,
    },
    history: mapHistory(raw.statusHistory),
    notes: mapNotes(raw.adminNotes),
    hasPhoto: Boolean(raw.photoPath),
  };
}

/** Page size at or below the backend's 100-item cap. */
const PAGE_LIMIT = 100;

/**
 * Safety ceiling so a very large dataset cannot trigger unbounded requests. If
 * the workspace exceeds it we fail loudly rather than silently showing a
 * partial list as if it were complete.
 */
const MAX_PAGES = 50;

export async function fetchAllReports(signal?: AbortSignal): Promise<Report[]> {
  const collected: Report[] = [];
  let page = 1;

  for (;;) {
    const response = await apiFetch<BackendListResponse>(
      `/reports?page=${page}&limit=${PAGE_LIMIT}`,
      { signal },
    );

    for (const row of response.data ?? []) collected.push(mapReport(row));

    const totalPages = response.pagination?.totalPages ?? 1;
    if (page >= totalPages) break;

    if (page >= MAX_PAGES) {
      throw new Error(
        `This workspace has more reports than the dashboard loads at once ` +
          `(over ${MAX_PAGES * PAGE_LIMIT}). Refusing to show a partial list.`,
      );
    }
    page += 1;
  }

  return collected;
}

export async function fetchReport(id: string, signal?: AbortSignal): Promise<Report> {
  const raw = await apiFetch<BackendReport>(`/reports/${encodeURIComponent(id)}`, { signal });
  return mapReport(raw);
}

export async function updateReportStatus(id: string, status: ReportStatus): Promise<Report> {
  const raw = await apiFetch<BackendReport>(`/reports/${encodeURIComponent(id)}/status`, {
    method: 'PATCH',
    body: { status: STATUS_TO_BACKEND[status] },
  });
  return mapReport(raw);
}

export async function createAdminNote(id: string, content: string): Promise<AdminNote> {
  const raw = await apiFetch<BackendAdminNote>(`/reports/${encodeURIComponent(id)}/notes`, {
    method: 'POST',
    body: { content },
  });
  return {
    id: raw.id,
    body: raw.content,
    author: raw.admin?.name ?? 'Unknown administrator',
    createdAt: raw.createdAt,
  };
}

export async function fetchReportPhoto(id: string, signal?: AbortSignal): Promise<Blob> {
  return apiFetchBlob(`/reports/${encodeURIComponent(id)}/photo`, signal);
}
