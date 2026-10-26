import { useEffect, useState } from 'react';
import type { AdminAccount } from '../api/admins';
import { createAdmin, fetchAdmins } from '../api/admins';
import { formatDate } from '../lib/format';
import { IconUser } from '../components/ui/Icon';
import { PageHeader } from '../components/ui/PageHeader';
import { Panel } from '../components/ui/Panel';
import { inputClass, labelClass, buttonPrimaryClass, buttonSecondaryClass } from '../lib/styles';

interface AdminTableProps {
  admins: AdminAccount[];
}

function AdminTable({ admins }: AdminTableProps) {
  if (admins.length === 0) {
    return (
      <div className="rounded-xl border border-slate-200 bg-white shadow-sm p-4 sm:p-5">
        <p className="text-sm text-slate-500">No administrator accounts found.</p>
      </div>
    );
  }

  return (
    <div className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
      <table className="min-w-full border-collapse text-left text-sm">
        <thead>
          <tr className="border-b border-slate-200 bg-slate-50/80 text-[11px] tracking-wider text-slate-500 uppercase">
            <th scope="col" className="px-4 py-3 font-semibold">
              Name
            </th>
            <th scope="col" className="px-4 py-3 font-semibold">
              Email
            </th>
            <th scope="col" className="px-4 py-3 font-semibold">
              Role
            </th>
            <th scope="col" className="px-4 py-3 font-semibold text-left">
              Region
            </th>
            <th scope="col" className="px-4 py-3 font-semibold">
              Created
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-100">
          {admins.map((admin) => (
            <tr key={admin.id} className="border-b border-slate-100 last:border-0 hover:bg-slate-50/70">
              <td className="px-4 py-3 text-sm font-medium text-slate-900">
                {admin.name}
              </td>
              <td className="px-4 py-3 text-sm text-slate-600 truncate max-w-xs">
                {admin.email}
              </td>
              <td className="px-4 py-3 text-sm">
                <span className="inline-flex items-center rounded-full border border-civic-200 bg-civic-50 px-2 py-0.5 text-xs font-semibold text-civic-700 uppercase">
                  {admin.role}
                </span>
              </td>
              <td className="px-4 py-3 text-sm text-slate-600">
                {[
                  admin.district ?? undefined,
                  admin.state ?? undefined,
                ]
                  .filter(Boolean)
                  .join(', ') || '—'}
              </td>
              <td className="px-4 py-3 text-sm text-slate-500 whitespace-nowrap">
                {formatDate(admin.createdAt)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function AdminManagementPage() {
  const [admins, setAdmins] = useState<AdminAccount[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const [form, setForm] = useState({
    name: '',
    email: '',
    password: '',
    confirmPassword: '',
    state: '',
    district: '',
  });

  const [submitting, setSubmitting] = useState(false);
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});

  useEffect(() => {
    let mounted = true;

    (async () => {
      setLoading(true);
      setError(null);
      try {
        const data = await fetchAdmins();
        if (mounted) setAdmins(data);
      } catch {
        if (mounted) setError('Unable to load administrator accounts. Please try again.');
      } finally {
        if (mounted) setLoading(false);
      }
    })();

    return () => {
      mounted = false;
    };
  }, []);

  const validateForm = (): boolean => {
    const next: Record<string, string> = {};

    if (!form.name.trim()) next.name = 'Name is required.';
    if (!form.email.trim()) next.email = 'Email is required.';
    else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email.trim())) {
      next.email = 'Enter a valid email address.';
    }
    if (!form.password) next.password = 'Password is required.';
    else if (form.password.length < 8) {
      next.password = 'Password must be at least 8 characters.';
    }
    if (form.password !== form.confirmPassword) {
      next.confirmPassword = 'Passwords do not match.';
    }
    if (!form.state.trim()) next.state = 'State is required.';

    setFieldErrors(next);
    return Object.keys(next).length === 0;
  };

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    setError(null);
    setSuccess(null);

    if (!validateForm()) return;

    setSubmitting(true);
    try {
      await createAdmin({
        name: form.name.trim(),
        email: form.email.trim(),
        password: form.password,
        state: form.state.trim(),
        district: form.district.trim() || undefined,
      });

      setSuccess('Administrator account created successfully.');
      setForm({
        name: '',
        email: '',
        password: '',
        confirmPassword: '',
        state: '',
        district: '',
      });
      setFieldErrors({});

      const refreshed = await fetchAdmins();
      setAdmins(refreshed);
    } catch (err) {
      if (err instanceof Error) {
        setError(err.message || 'Failed to create administrator account.');
      } else {
        setError('Failed to create administrator account.');
      }
    } finally {
      setSubmitting(false);
    }
  };

  const handleChange = (field: keyof typeof form, value: string) => {
    setForm((prev) => ({ ...prev, [field]: value }));
    if (fieldErrors[field]) {
      setFieldErrors((prev) => {
        const next = { ...prev };
        delete next[field];
        return next;
      });
    }
  };

  const clearMessages = () => {
    setError(null);
    setSuccess(null);
  };

  return (
    <>
      <PageHeader
        title="Admin Management"
        description="View existing administrator accounts and create additional administrator accounts."
        meta={<span className="inline-flex items-center rounded-full border border-slate-200 bg-slate-50 px-3 py-1 text-xs font-medium text-slate-700">
          Administrators
        </span>}
      />

      <Panel
        title="Existing administrators"
        description="All administrator accounts registered in the CivicLens backend."
        action={<IconUser size={16} className="text-slate-400" />}
        className="mb-5"
      >
        {loading ? (
          <div className="h-64 flex items-center justify-center">
            <p className="text-sm text-slate-500">Loading administrators…</p>
          </div>
        ) : error ? (
          <div className="rounded-xl border border-slate-200 bg-white shadow-sm p-4 sm:p-5">
            <p className="text-sm text-slate-600">{error}</p>
          </div>
        ) : (
          <AdminTable admins={admins} />
        )}
      </Panel>

      <Panel
        title="Create administrator"
        description="Create a new administrator account. The role is always ADMIN and is assigned server-side."
      >
        {success ? (
          <div className="mb-4 rounded-lg border border-civic-200 bg-civic-50 px-4 py-3 text-sm text-civic-700">
            {success}
          </div>
        ) : null}

        <form onSubmit={handleSubmit} className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <div className="col-span-full sm:col-span-2 lg:col-span-4">
            <label htmlFor="admin-name" className={labelClass}>
              Full name
            </label>
            <input
              id="admin-name"
              name="name"
              type="text"
              value={form.name}
              onChange={(event) => handleChange('name', event.target.value)}
              placeholder="Asha Rao"
              className={inputClass}
              autoFocus
            />
            {fieldErrors.name ? (
              <p className="mt-1 text-xs text-rose-600">{fieldErrors.name}</p>
            ) : null}
          </div>

          <div className="col-span-full sm:col-span-2 lg:col-span-4">
            <label htmlFor="admin-email" className={labelClass}>
              Official email
            </label>
            <input
              id="admin-email"
              name="email"
              type="email"
              value={form.email}
              onChange={(event) => handleChange('email', event.target.value)}
              placeholder="asha.rao@example.com"
              className={inputClass}
            />
            {fieldErrors.email ? (
              <p className="mt-1 text-xs text-rose-600">{fieldErrors.email}</p>
            ) : null}
          </div>

          <div className="col-span-full sm:col-span-2 lg:col-span-2">
            <label htmlFor="admin-password" className={labelClass}>
              Password
            </label>
            <input
              id="admin-password"
              name="password"
              type="password"
              value={form.password}
              onChange={(event) => handleChange('password', event.target.value)}
              placeholder="••••••••"
              className={inputClass}
            />
            {fieldErrors.password ? (
              <p className="mt-1 text-xs text-rose-600">{fieldErrors.password}</p>
            ) : null}
          </div>

          <div className="col-span-full sm:col-span-2 lg:col-span-2">
            <label htmlFor="admin-confirm-password" className={labelClass}>
              Confirm password
            </label>
            <input
              id="admin-confirm-password"
              name="confirmPassword"
              type="password"
              value={form.confirmPassword}
              onChange={(event) => handleChange('confirmPassword', event.target.value)}
              placeholder="••••••••"
              className={inputClass}
            />
            {fieldErrors.confirmPassword ? (
              <p className="mt-1 text-xs text-rose-600">{fieldErrors.confirmPassword}</p>
            ) : null}
          </div>

          <div className="col-span-full sm:col-span-1 lg:col-span-1">
            <label htmlFor="admin-state" className={labelClass}>
              State <span className="text-rose-600">*</span>
            </label>
            <input
              id="admin-state"
              name="state"
              type="text"
              value={form.state}
              onChange={(event) => handleChange('state', event.target.value)}
              placeholder="Maharashtra"
              className={inputClass}
            />
            {fieldErrors.state ? (
              <p className="mt-1 text-xs text-rose-600">{fieldErrors.state}</p>
            ) : null}
          </div>

          <div className="col-span-full sm:col-span-1 lg:col-span-1">
            <label htmlFor="admin-district" className={labelClass}>
              District (optional)
            </label>
            <input
              id="admin-district"
              name="district"
              type="text"
              value={form.district}
              onChange={(event) => handleChange('district', event.target.value)}
              placeholder="Pune"
              className={inputClass}
            />
          </div>

          <div className="col-span-full sm:col-span-2 lg:col-span-4 flex gap-2">
            <button
              type="submit"
              disabled={submitting}
              className={submitting ? `${buttonPrimaryClass} opacity-70` : buttonPrimaryClass}
            >
              {submitting ? 'Creating…' : 'Create administrator'}
            </button>
            <button
              type="button"
              onClick={() => {
                setForm({
                  name: '',
                  email: '',
                  password: '',
                  confirmPassword: '',
                  state: '',
                  district: '',
                });
                setFieldErrors({});
                clearMessages();
              }}
              className={buttonSecondaryClass}
            >
              Reset
            </button>
          </div>
        </form>
      </Panel>
    </>
  );
}
