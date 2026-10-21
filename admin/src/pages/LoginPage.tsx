import { useState } from 'react';
import type { FormEvent } from 'react';
import { useSession } from '../auth/sessionContext';
import { buttonPrimaryClass, inputClass, labelClass } from '../lib/styles';
import { IconAlert, IconLock } from '../components/ui/Icon';

export function LoginPage() {
  const { login, expired, clearExpired } = useSession();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async (event: FormEvent) => {
    event.preventDefault();
    if (submitting) return;
    clearExpired();
    setError(null);

    if (!email.trim() || !password) {
      setError('Enter your email address and password.');
      return;
    }

    setSubmitting(true);
    const result = await login(email.trim(), password);
    setSubmitting(false);
    // The password is never logged or retained beyond the request.
    setPassword('');
    if (!result.ok) {
      setError(result.error ?? 'Sign-in failed.');
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-50 px-4 py-10">
      <div className="w-full max-w-md">
        <div className="mb-6 flex items-center gap-3">
          <img
            src="/civiclens.png"
            alt=""
            width={44}
            height={44}
            className="size-11 rounded-lg object-contain"
          />
          <div className="leading-tight">
            <p className="text-lg font-bold tracking-tight text-slate-900">CivicLens</p>
            <p className="text-xs font-semibold tracking-wider text-civic-700 uppercase">
              Admin Dashboard
            </p>
          </div>
        </div>

        <div className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
          <div className="mb-5 flex items-start gap-3">
            <span className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-civic-50 text-civic-700">
              <IconLock size={18} />
            </span>
            <div>
              <h1 className="text-lg font-semibold text-slate-900">Administrator sign-in</h1>
              <p className="mt-0.5 text-sm text-slate-500">
                Sign in with an account that has the administrator role.
              </p>
            </div>
          </div>

          {expired ? (
            <p
              role="status"
              className="mb-4 flex items-start gap-2 rounded-lg bg-amber-50 px-3 py-2 text-xs leading-relaxed text-amber-800"
            >
              <IconAlert size={14} className="mt-0.5 shrink-0" />
              Your session expired. Please sign in again.
            </p>
          ) : null}

          <form onSubmit={handleSubmit} noValidate>
            <div className="mb-4">
              <label htmlFor="login-email" className={labelClass}>
                Email
              </label>
              <input
                id="login-email"
                type="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                className={inputClass}
                autoComplete="username"
                autoFocus
                required
              />
            </div>

            <div className="mb-5">
              <label htmlFor="login-password" className={labelClass}>
                Password
              </label>
              <input
                id="login-password"
                type="password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                className={inputClass}
                autoComplete="current-password"
                required
              />
            </div>

            {error ? (
              <p
                role="alert"
                className="mb-4 flex items-start gap-2 rounded-lg bg-rose-50 px-3 py-2 text-xs leading-relaxed text-rose-700"
              >
                <IconAlert size={14} className="mt-0.5 shrink-0" />
                {error}
              </p>
            ) : null}

            <button
              type="submit"
              disabled={submitting}
              className={`${buttonPrimaryClass} w-full`}
            >
              {submitting ? 'Signing in…' : 'Sign in'}
            </button>
          </form>

          <p className="mt-5 text-xs leading-relaxed text-slate-400">
            Signed-in sessions are held in this browser tab only and are cleared when you sign
            out or close the tab. Credentials are sent to the CivicLens backend and are never
            stored in this application.
          </p>
        </div>
      </div>
    </div>
  );
}
