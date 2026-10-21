import { useEffect, useRef, useState } from 'react';
import { cn } from '../../lib/cn';
import { initials } from '../../lib/format';
import { navigate } from '../../router';
import { useStore } from '../../data/store';
import { useSession } from '../../auth/sessionContext';
import { IconChevronDown, IconLogout, IconSettings } from '../ui/Icon';

export function AccountMenu() {
  const { profile } = useStore();
  const { logout } = useSession();
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const buttonRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    const onPointerDown = (event: MouseEvent) => {
      if (!containerRef.current?.contains(event.target as Node)) setOpen(false);
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setOpen(false);
        buttonRef.current?.focus();
      }
    };
    document.addEventListener('mousedown', onPointerDown);
    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('mousedown', onPointerDown);
      document.removeEventListener('keydown', onKeyDown);
    };
  }, [open]);

  const goToSettings = () => {
    setOpen(false);
    navigate('/settings');
  };

  const handleLogout = () => {
    setOpen(false);
    logout();
    navigate('/');
  };

  return (
    <div ref={containerRef} className="relative">
      <button
        ref={buttonRef}
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
        className="flex items-center gap-2 rounded-lg border border-transparent px-1.5 py-1.5 transition hover:border-slate-200 hover:bg-white"
      >
        <span className="flex size-8 items-center justify-center rounded-full bg-civic-700 text-xs font-bold text-white">
          {initials(profile.name)}
        </span>
        <span className="hidden text-left md:block">
          <span className="block text-sm leading-tight font-semibold text-slate-900">
            {profile.name}
          </span>
          <span className="block text-xs leading-tight text-slate-500">{profile.role}</span>
        </span>
        <IconChevronDown
          size={16}
          className={cn('hidden text-slate-400 transition md:block', open && 'rotate-180')}
        />
        <span className="sr-only">Open account menu</span>
      </button>

      {open ? (
        <div
          role="menu"
          aria-label="Account"
          className="absolute right-0 z-50 mt-2 w-72 rounded-xl border border-slate-200 bg-white p-3 shadow-lg shadow-slate-900/10"
        >
          <div className="flex items-start gap-3 border-b border-slate-100 pb-3">
            <span className="flex size-10 shrink-0 items-center justify-center rounded-full bg-civic-700 text-sm font-bold text-white">
              {initials(profile.name)}
            </span>
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold text-slate-900">{profile.name}</p>
              <p className="truncate text-xs text-slate-500">{profile.email}</p>
              <p className="mt-0.5 text-xs font-medium text-slate-500">{profile.role}</p>
            </div>
          </div>

          <button
            type="button"
            role="menuitem"
            onClick={goToSettings}
            className="mt-2 flex w-full items-center gap-2 rounded-lg px-2.5 py-2 text-sm font-medium text-slate-700 transition hover:bg-slate-100 hover:text-slate-900"
          >
            <IconSettings size={17} />
            Account settings
          </button>

          <button
            type="button"
            role="menuitem"
            onClick={handleLogout}
            className="flex w-full items-center gap-2 rounded-lg px-2.5 py-2 text-sm font-medium text-rose-700 transition hover:bg-rose-50"
          >
            <IconLogout size={17} />
            Sign out
          </button>
        </div>
      ) : null}
    </div>
  );
}
