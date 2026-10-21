export interface SessionUser {
  id: string;
  name: string;
  email: string;
  role: string;
  state?: string | null;
  district?: string | null;
}

export interface Session {
  token: string;
  user: SessionUser;
}

/**
 * Prototype-only session storage.
 *
 * The JWT is kept in sessionStorage rather than localStorage so it does not
 * survive the tab being closed, and it is cleared explicitly on logout. This is
 * still readable by any script running on the page, so it is not a hardened
 * auth design: a production build should use an httpOnly, SameSite cookie
 * session. This trade-off is deliberate for the current prototype.
 */
export const SESSION_STORAGE_KEY = 'civiclens.admin.session.v1';

/** Fired whenever the backend answers 401 so the app can drop the session. */
export const UNAUTHORIZED_EVENT = 'civiclens:unauthorized';

export class ApiError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
  }
}

export function readStoredSession(): Session | null {
  try {
    const raw = window.sessionStorage.getItem(SESSION_STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<Session>;
    if (!parsed || typeof parsed.token !== 'string' || !parsed.user) return null;
    return parsed as Session;
  } catch {
    return null;
  }
}

export function writeStoredSession(session: Session): void {
  try {
    window.sessionStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(session));
  } catch {
    // Storage can be unavailable (private mode); the in-memory session still works.
  }
}

export function clearStoredSession(): void {
  try {
    window.sessionStorage.removeItem(SESSION_STORAGE_KEY);
  } catch {
    // Ignore storage failures.
  }
}

function extractMessage(body: unknown, fallback: string): string {
  if (body && typeof body === 'object' && 'error' in body) {
    const value = (body as { error?: unknown }).error;
    if (typeof value === 'string' && value.trim()) return value;
  }
  return fallback;
}

interface ApiFetchOptions {
  method?: string;
  body?: unknown;
  /** Set false for endpoints that must not be tied to the current session (login). */
  auth?: boolean;
  /** Set false to suppress the global 401 handling (e.g. the login request itself). */
  handleUnauthorized?: boolean;
  signal?: AbortSignal;
}

/**
 * Performs an authenticated JSON request against the backend.
 *
 * Relative `/api/...` URLs go through the Vite dev proxy in development and
 * resolve to same-origin in a production build. A 401 response clears the
 * stored session and notifies the app so it can return to the login screen.
 */
export async function apiFetch<T>(path: string, options: ApiFetchOptions = {}): Promise<T> {
  const { method = 'GET', body, auth = true, handleUnauthorized = true, signal } = options;

  const headers = new Headers();
  if (body !== undefined) headers.set('Content-Type', 'application/json');

  if (auth) {
    const session = readStoredSession();
    if (session) headers.set('Authorization', `Bearer ${session.token}`);
  }

  const response = await fetch(`/api${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    signal,
  });

  if (response.status === 401 && handleUnauthorized) {
    window.dispatchEvent(new Event(UNAUTHORIZED_EVENT));
  }

  if (!response.ok) {
    let parsed: unknown;
    try {
      parsed = await response.json();
    } catch {
      parsed = null;
    }
    throw new ApiError(response.status, extractMessage(parsed, `Request failed (${response.status})`));
  }

  if (response.status === 204) return undefined as T;

  return (await response.json()) as T;
}

/**
 * Fetches a report's evidence image as a Blob using the session token. Images
 * are not passive static files: the backend requires the Authorization header,
 * so they cannot be loaded through a bare <img src>.
 */
export async function apiFetchBlob(path: string, signal?: AbortSignal): Promise<Blob> {
  const headers = new Headers();
  const session = readStoredSession();
  if (session) headers.set('Authorization', `Bearer ${session.token}`);

  const response = await fetch(`/api${path}`, { headers, signal });

  if (response.status === 401) {
    window.dispatchEvent(new Event(UNAUTHORIZED_EVENT));
  }

  if (!response.ok) {
    throw new ApiError(response.status, `Image request failed (${response.status})`);
  }

  return response.blob();
}
