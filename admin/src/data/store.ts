import { createContext, useContext } from 'react';
import type {
  ActivityItem,
  AdminProfile,
  Preferences,
  Report,
  ReportStatus,
} from '../types';

export interface StoreValue {
  reports: Report[];
  activity: ActivityItem[];
  profile: AdminProfile;
  preferences: Preferences;
  loading: boolean;
  error: string | null;
  reload: () => void;
  getReport: (id: string) => Report | undefined;
  setStatus: (reportId: string, status: ReportStatus) => Promise<void>;
  addNote: (reportId: string, body: string) => Promise<void>;
  setPreferences: (patch: Partial<Preferences>) => void;
}

export const StoreContext = createContext<StoreValue | null>(null);

export function useStore(): StoreValue {
  const value = useContext(StoreContext);
  if (!value) {
    throw new Error('useStore must be used inside a StoreProvider');
  }
  return value;
}
