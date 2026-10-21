import type { Category, CategoryId, ReportStatus } from '../types';

export const STATUSES: ReportStatus[] = [
  'Submitted',
  'Under Review',
  'In Progress',
  'Resolved',
  'Rejected',
];

export const STATUS_HEX: Record<ReportStatus, string> = {
  Submitted: '#64748b',
  'Under Review': '#d97706',
  'In Progress': '#2563eb',
  Resolved: '#059669',
  Rejected: '#e11d48',
};

export const CATEGORIES: Category[] = [
  { id: 'roads', label: 'Roads and Potholes', color: '#2563eb' },
  { id: 'streetlights', label: 'Streetlights', color: '#7c3aed' },
  { id: 'water', label: 'Water Supply', color: '#0891b2' },
  { id: 'waste', label: 'Waste Management', color: '#16a34a' },
  { id: 'drainage', label: 'Drainage', color: '#d97706' },
  { id: 'safety', label: 'Public Safety', color: '#dc2626' },
];

const CATEGORY_LOOKUP: Record<CategoryId, Category> = {
  roads: CATEGORIES[0],
  streetlights: CATEGORIES[1],
  water: CATEGORIES[2],
  waste: CATEGORIES[3],
  drainage: CATEGORIES[4],
  safety: CATEGORIES[5],
};

export function categoryLabel(id: CategoryId): string {
  return CATEGORY_LOOKUP[id]?.label ?? id;
}

export function isCategoryId(value: string): value is CategoryId {
  return Object.prototype.hasOwnProperty.call(CATEGORY_LOOKUP, value);
}

export function isReportStatus(value: string): value is ReportStatus {
  return (STATUSES as string[]).includes(value);
}

