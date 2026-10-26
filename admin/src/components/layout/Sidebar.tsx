import { useEffect, useRef } from 'react';
import type { ComponentType } from 'react';
import { cn } from '../../lib/cn';
import type { Route } from '../../router';
import type { IconProps } from '../ui/Icon';
import {
  IconActivity,
  IconClose,
  IconDatabase,
  IconMap,
  IconOverview,
  IconReports,
  IconSettings,
  IconUser,
} from '../ui/Icon';

interface NavItem {
  page: Route['page'];
  label: string;
  description: string;
  path: string;
  icon: ComponentType<IconProps>;
}

const NAV_ITEMS: NavItem[] = [
  {
    page: 'overview',
    label: 'Overview',
    description: 'Dashboard summary',
    path: '/',
    icon: IconOverview,
  },
  {
    page: 'reports',
    label: 'Reports',
    description: 'Search and manage',
    path: '/reports',
    icon: IconReports,
  },
  {
    page: 'map',
    label: 'Reports Map',
    description: 'Spatial view',
    path: '/map',
    icon: IconMap,
  },
  {
    page: 'activity',
    label: 'Activity',
    description: 'Administrative log',
    path: '/activity',
    icon: IconActivity,
  },
  {
    page: 'settings',
    label: 'Settings',
    description: 'Preferences',
    path: '/settings',
    icon: IconSettings,
  },
  {
    page: 'admin',
    label: 'Admin Management',
    description: 'Manage administrator accounts',
    path: '/admin',
    icon: IconUser,
  },
];

function isActive(item: NavItem, route: Route): boolean {
  if (item.page === 'reports') return route.page === 'reports' || route.page === 'report';
  if (item.page === 'map') return route.page === 'map';
  return route.page === item.page;
}

function Brand() {
  return (
    <div className="flex items-center gap-3 px-5 py-5">
      <img
        src="/civiclens.png"
        alt=""
        width={36}
        height={36}
        className="size-9 rounded-lg object-contain"
      />
      <div className="min-w-0 leading-tight">
        <p className="truncate text-[15px] font-bold tracking-tight text-slate-900">
          CivicLens
        </p>
        <p className="text-[11px] font-semibold tracking-wider text-civic-700 uppercase">
          Admin Dashboard
        </p>
      </div>
    </div>
  );
}

export function Sidebar({
  route,
  open,
  onClose,
}: {
  route: Route;
  open: boolean;
  onClose: () => void;
}) {
  const closeButtonRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (open) closeButtonRef.current?.focus();
  }, [open]);

  return (
    <>
      <div
        className={cn(
          'fixed inset-0 z-30 bg-slate-900/40 transition-opacity lg:hidden',
          open ? 'opacity-100' : 'pointer-events-none opacity-0',
        )}
        aria-hidden="true"
        onClick={onClose}
      />
      <aside
        id="app-sidebar"
        aria-label="Primary navigation"
        onKeyDown={(event) => {
          if (event.key === 'Escape') onClose();
        }}
        className={cn(
          'fixed inset-y-0 left-0 z-40 flex w-64 flex-col border-r border-slate-200 bg-white transition-transform duration-200 lg:translate-x-0',
          open ? 'translate-x-0' : '-translate-x-full',
        )}
      >
        <div className="flex items-center justify-between border-b border-slate-100 pr-3">
          <Brand />
          <button
            ref={closeButtonRef}
            type="button"
            onClick={onClose}
            className="rounded-lg p-2 text-slate-500 transition hover:bg-slate-100 hover:text-slate-800 lg:hidden"
          >
            <IconClose size={18} />
            <span className="sr-only">Close navigation</span>
          </button>
        </div>

        <nav className="flex-1 overflow-y-auto px-3 py-4">
          <ul className="space-y-1">
            {NAV_ITEMS.map((item) => {
              const Icon = item.icon;
              const active = isActive(item, route);
              return (
                <li key={item.page}>
                  <a
                    href={`#${item.path}`}
                    aria-current={active ? 'page' : undefined}
                    onClick={onClose}
                    className={cn(
                      'group flex items-center gap-3 rounded-lg px-3 py-2.5 transition',
                      active
                        ? 'bg-civic-700 text-white shadow-sm'
                        : 'text-slate-700 hover:bg-slate-100 hover:text-slate-900',
                    )}
                  >
                    <Icon
                      size={19}
                      className={active ? 'text-white' : 'text-slate-400 group-hover:text-slate-600'}
                    />
                    <span className="min-w-0">
                      <span className="block text-sm font-semibold">{item.label}</span>
                      <span
                        className={cn(
                          'block text-xs',
                          active ? 'text-civic-100' : 'text-slate-400',
                        )}
                      >
                        {item.description}
                      </span>
                    </span>
                  </a>
                </li>
              );
            })}
          </ul>
        </nav>

        <div className="border-t border-slate-100 p-4">
          <div className="rounded-lg bg-slate-50 p-3">
            <div className="mb-1.5 flex flex-wrap items-center gap-x-2 gap-y-1">
              <IconDatabase size={16} className="text-slate-400" />
              <span className="text-[11px] font-bold tracking-wider text-slate-500 uppercase">
                Connected workspace
              </span>
            </div>
            <p className="text-xs leading-relaxed text-slate-500">
              Reports, status changes and administrative notes are read from and written to the
              CivicLens backend API.
            </p>
          </div>
        </div>
      </aside>
    </>
  );
}
