import { useCallback, useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import type { ActivityItem, AdminProfile, Preferences, Report, ReportStatus } from '../types';
import { fetchAllReports, createAdminNote, updateReportStatus } from '../api/reports';
import { useSession } from '../auth/sessionContext';
import { StoreContext } from './store';
import type { StoreValue } from './store';

const PREFERENCES_STORAGE_KEY = 'civiclens.admin.preferences.v1';

const DEFAULT_PREFERENCES: Preferences = { density: 'comfortable' };

function readPreferences(): Preferences {
  try {
    const raw = window.localStorage.getItem(PREFERENCES_STORAGE_KEY);
    if (!raw) return DEFAULT_PREFERENCES;
    const parsed = JSON.parse(raw) as Partial<Preferences>;
    if (parsed?.density === 'compact' || parsed?.density === 'comfortable') {
      return { density: parsed.density };
    }
  } catch {
    // Ignore malformed or unavailable storage.
  }
  return DEFAULT_PREFERENCES;
}

function toMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return 'Reports could not be loaded from the backend.';
}

/**
 * Builds the activity log from the only persisted administrative events the
 * backend exposes: status-history rows and administrator notes. No events are
 * fabricated, and status changes are shown without an actor because the
 * StatusHistory model does not store one.
 */
function deriveActivity(reports: Report[]): ActivityItem[] {
  const items: ActivityItem[] = [];

  for (const report of reports) {
    for (const entry of report.history) {
      items.push({
        id: `status-${entry.id}`,
        type: 'status',
        message: `changed ${report.id} to ${entry.status}`,
        reportId: report.id,
        at: entry.changedAt,
      });
    }
    for (const note of report.notes) {
      items.push({
        id: `note-${note.id}`,
        type: 'note',
        actor: note.author,
        message: `added an administrative note to ${report.id}`,
        reportId: report.id,
        at: note.createdAt,
      });
    }
  }

  return items.sort((a, b) => b.at.localeCompare(a.at));
}

function profileFromSession(name: string, email: string, role: string): AdminProfile {
  return {
    name,
    email,
    role: role === 'ADMIN' ? 'Administrator' : role,
  };
}

export function StoreProvider({ children }: { children: ReactNode }) {
  const { session } = useSession();
  const [reports, setReports] = useState<Report[]>([]);
  const [preferences, setPreferencesState] = useState<Preferences>(() => readPreferences());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  useEffect(() => {
    if (!session) return;
    const controller = new AbortController();
    fetchAllReports(controller.signal).then(
      (next) => {
        if (controller.signal.aborted) return;
        setReports(next);
        setLoading(false);
      },
      (loadError) => {
        if (controller.signal.aborted) return;
        setError(toMessage(loadError));
        setLoading(false);
      },
    );
    return () => controller.abort();
  }, [reloadToken, session]);

  const reload = useCallback(() => {
    setError(null);
    setLoading(true);
    setReloadToken((token) => token + 1);
  }, []);

  const setPreferences = useCallback((patch: Partial<Preferences>) => {
    setPreferencesState((current) => {
      const next = { ...current, ...patch };
      try {
        window.localStorage.setItem(PREFERENCES_STORAGE_KEY, JSON.stringify(next));
      } catch {
        // Storage is optional for a UI preference.
      }
      return next;
    });
  }, []);

  const setStatus = useCallback(async (reportId: string, status: ReportStatus) => {
    const updated = await updateReportStatus(reportId, status);
    setReports((current) =>
      current.map((report) => (report.id === updated.id ? updated : report)),
    );
  }, []);

  const addNote = useCallback(async (reportId: string, body: string) => {
    const trimmed = body.trim();
    if (!trimmed) return;
    const note = await createAdminNote(reportId, trimmed);
    setReports((current) =>
      current.map((report) =>
        report.id === reportId ? { ...report, notes: [note, ...report.notes] } : report,
      ),
    );
  }, []);

  const activity = useMemo(() => deriveActivity(reports), [reports]);

  const profile = useMemo<AdminProfile>(() => {
    if (!session) {
      return { name: 'Unknown administrator', email: '', role: 'Administrator' };
    }
    return profileFromSession(session.user.name, session.user.email, session.user.role);
  }, [session]);

  const value = useMemo<StoreValue>(() => {
    return {
      reports,
      activity,
      profile,
      preferences,
      loading,
      error,
      reload,
      getReport: (id: string) => reports.find((report) => report.id === id),
      setStatus,
      addNote,
      setPreferences,
    };
  }, [reports, activity, profile, preferences, loading, error, reload, setStatus, addNote, setPreferences]);

  return <StoreContext.Provider value={value}>{children}</StoreContext.Provider>;
}
