export type ReportStatus =
  | 'Submitted'
  | 'Under Review'
  | 'In Progress'
  | 'Resolved'
  | 'Rejected';

export type CategoryId =
  | 'roads'
  | 'streetlights'
  | 'water'
  | 'waste'
  | 'drainage'
  | 'safety';

export interface Category {
  id: CategoryId;
  label: string;
  color: string;
}

export interface Coordinates {
  lat: number;
  lng: number;
}

export interface ReportLocation {
  area: string;
  address: string;
  landmark?: string;
  coordinates?: Coordinates;
}

export interface StatusHistoryEntry {
  id: string;
  status: ReportStatus;
  changedAt: string;
  /** The backend records no actor for a status transition, so this is absent. */
  changedBy?: string;
  previousStatus?: ReportStatus;
}

export interface AdminNote {
  id: string;
  body: string;
  author: string;
  createdAt: string;
}

export type ReportPriority = 'Low' | 'Normal' | 'High';

export interface Report {
  id: string;
  title: string;
  description: string;
  categoryId: CategoryId;
  status: ReportStatus;
  /** Not supplied by the backend; rendered honestly as unavailable. */
  priority?: ReportPriority;
  submittedAt: string;
  updatedAt: string;
  /** Not supplied by the backend; rendered honestly as unavailable. */
  assignee?: string;
  reporterName?: string;
  reporterEmail?: string;
  location: ReportLocation;
  history: StatusHistoryEntry[];
  notes: AdminNote[];
  hasPhoto: boolean;
}

export type ActivityType = 'status' | 'note' | 'system';

export interface ActivityItem {
  id: string;
  type: ActivityType;
  /** Absent for status changes: the backend does not record the actor. */
  actor?: string;
  message: string;
  reportId?: string;
  at: string;
}

export interface AdminProfile {
  name: string;
  email: string;
  role: string;
  department?: string;
}

export type TableDensity = 'comfortable' | 'compact';

export interface Preferences {
  density: TableDensity;
}
