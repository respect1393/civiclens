import { createContext, useContext } from 'react';
import type { Session } from '../api/client';

export interface LoginResult {
  ok: boolean;
  error?: string;
}

export interface SessionValue {
  session: Session | null;
  /** True when the last session ended because the token expired or was rejected. */
  expired: boolean;
  login: (email: string, password: string) => Promise<LoginResult>;
  logout: () => void;
  clearExpired: () => void;
}

export const SessionContext = createContext<SessionValue | null>(null);

export function useSession(): SessionValue {
  const value = useContext(SessionContext);
  if (!value) {
    throw new Error('useSession must be used inside a SessionProvider');
  }
  return value;
}
