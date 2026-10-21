import { useCallback, useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import {
  UNAUTHORIZED_EVENT,
  clearStoredSession,
  readStoredSession,
  writeStoredSession,
} from '../api/client';
import type { Session, SessionUser } from '../api/client';
import { SessionContext } from './sessionContext';
import type { LoginResult, SessionValue } from './sessionContext';

const ADMIN_ROLE = 'ADMIN';

export function SessionProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(() => readStoredSession());
  const [expired, setExpired] = useState(false);

  const logout = useCallback(() => {
    clearStoredSession();
    setSession(null);
  }, []);

  useEffect(() => {
    const onUnauthorized = () => {
      if (!readStoredSession()) return;
      setExpired(true);
      clearStoredSession();
      setSession(null);
    };
    window.addEventListener(UNAUTHORIZED_EVENT, onUnauthorized);
    return () => window.removeEventListener(UNAUTHORIZED_EVENT, onUnauthorized);
  }, []);

  const login = useCallback(async (email: string, password: string): Promise<LoginResult> => {
    try {
      const response = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password }),
      });

      if (!response.ok) {
        if (response.status === 401) {
          return { ok: false, error: 'Incorrect email or password.' };
        }
        if (response.status === 429) {
          return {
            ok: false,
            error: 'Too many attempts. Please wait a moment and try again.',
          };
        }
        if (response.status === 400) {
          return { ok: false, error: 'Enter a valid email address and password.' };
        }
        return { ok: false, error: 'Sign-in failed. Please try again.' };
      }

      const data = (await response.json()) as { user?: SessionUser; token?: string };
      if (!data.user || typeof data.token !== 'string') {
        return { ok: false, error: 'The server returned an unexpected response.' };
      }

      if (data.user.role !== ADMIN_ROLE) {
        return {
          ok: false,
          error: 'This account does not have administrator access.',
        };
      }

      const next: Session = { token: data.token, user: data.user };
      writeStoredSession(next);
      setExpired(false);
      setSession(next);
      return { ok: true };
    } catch {
      return { ok: false, error: 'Cannot reach the CivicLens backend. Is it running?' };
    }
  }, []);

  const clearExpired = useCallback(() => setExpired(false), []);

  const value = useMemo<SessionValue>(
    () => ({ session, expired, login, logout, clearExpired }),
    [session, expired, login, logout, clearExpired],
  );

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}
