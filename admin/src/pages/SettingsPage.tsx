import { useStore } from '../data/store';
import { useSession } from '../auth/sessionContext';
import type { TableDensity } from '../types';
import { cn } from '../lib/cn';
import { IconInfo, IconLock, IconSettings, IconUser } from '../components/ui/Icon';
import { PageHeader } from '../components/ui/PageHeader';
import { Panel } from '../components/ui/Panel';

const DENSITY_OPTIONS: Array<{ value: TableDensity; label: string; description: string }> = [
  {
    value: 'comfortable',
    label: 'Comfortable',
    description: 'More padding in report tables for easier scanning.',
  },
  {
    value: 'compact',
    label: 'Compact',
    description: 'Tighter rows so more reports fit on screen.',
  },
];

export function SettingsPage() {
  const { profile, preferences, setPreferences } = useStore();
  const { session } = useSession();

  return (
    <>
      <PageHeader
        title="Settings"
        description="Signed-in administrator profile and interface preferences."
      />

      <div className="grid grid-cols-1 gap-5 lg:grid-cols-2">
        <Panel
          title="Administrator profile"
          description="Taken from the signed-in backend session"
          action={<IconUser size={16} className="text-slate-400" />}
        >
          <dl className="space-y-3 text-sm">
            <div className="flex justify-between gap-3">
              <dt className="text-slate-500">Name</dt>
              <dd className="font-medium text-slate-800">{profile.name}</dd>
            </div>
            <div className="flex justify-between gap-3">
              <dt className="text-slate-500">Email</dt>
              <dd className="truncate font-medium text-slate-800">{profile.email}</dd>
            </div>
            <div className="flex justify-between gap-3">
              <dt className="text-slate-500">Role</dt>
              <dd className="font-medium text-slate-800">{profile.role}</dd>
            </div>
            {session?.user.state || session?.user.district ? (
              <div className="flex justify-between gap-3">
                <dt className="text-slate-500">Region</dt>
                <dd className="font-medium text-slate-800">
                  {[session?.user.district, session?.user.state].filter(Boolean).join(', ')}
                </dd>
              </div>
            ) : null}
          </dl>
          <div className="mt-5 flex gap-2 rounded-lg bg-slate-50 p-3">
            <IconInfo size={16} className="mt-0.5 shrink-0 text-slate-400" />
            <p className="text-xs leading-relaxed text-slate-500">
              Profile details come from the backend account and cannot be edited here. Use the
              account menu to sign out.
            </p>
          </div>
        </Panel>

        <Panel
          title="Interface preferences"
          description="Applied across the dashboard"
          action={<IconSettings size={16} className="text-slate-400" />}
        >
          <fieldset>
            <legend className="mb-2 text-xs font-semibold tracking-wide text-slate-700">
              Table density
            </legend>
            <div className="space-y-2">
              {DENSITY_OPTIONS.map((option) => {
                const checked = preferences.density === option.value;
                return (
                  <label
                    key={option.value}
                    className={cn(
                      'flex cursor-pointer items-start gap-3 rounded-lg border p-3 transition',
                      checked
                        ? 'border-civic-300 bg-civic-50/60'
                        : 'border-slate-200 hover:border-slate-300 hover:bg-slate-50',
                    )}
                  >
                    <input
                      type="radio"
                      name="density"
                      value={option.value}
                      checked={checked}
                      onChange={() => setPreferences({ density: option.value })}
                      className="mt-1 size-4 accent-civic-700"
                    />
                    <span>
                      <span className="block text-sm font-semibold text-slate-800">
                        {option.label}
                      </span>
                      <span className="mt-0.5 block text-xs leading-relaxed text-slate-500">
                        {option.description}
                      </span>
                    </span>
                  </label>
                );
              })}
            </div>
          </fieldset>

          <div className="mt-5 flex gap-2 rounded-lg bg-slate-50 p-3">
            <IconInfo size={16} className="mt-0.5 shrink-0 text-slate-400" />
            <p className="text-xs leading-relaxed text-slate-500">
              Preferences are stored in this browser only. They are a local display setting and
              are not sent to the backend.
            </p>
          </div>
        </Panel>

        <Panel
          title="Session and security"
          description="How sign-in is handled in this build"
          action={<IconLock size={16} className="text-slate-400" />}
          className="lg:col-span-2"
        >
          <ul className="space-y-2 text-sm leading-relaxed text-slate-600">
            <li>
              Sign-in uses <code className="font-mono text-slate-700">POST /api/auth/login</code>.
              Accounts without the administrator role are rejected.
            </li>
            <li>
              The session token is kept in this browser tab&apos;s session storage and is cleared
              on sign-out. It is not persisted in local storage.
            </li>
            <li>
              This is a prototype trade-off: a script running on the page could read the token. A
              production deployment should use an httpOnly, SameSite cookie session instead.
            </li>
            <li>
              If the backend rejects the token with a 401, the session is cleared and you are
              returned to the sign-in screen.
            </li>
          </ul>
        </Panel>
      </div>
    </>
  );
}
