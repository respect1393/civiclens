import { cn } from '../../lib/cn';
import { pageMeta } from '../../lib/pageMeta';
import type { Route } from '../../router';
import { IconChevronRight, IconMenu } from '../ui/Icon';
import { AccountMenu } from './AccountMenu';

export function Topbar({ route, onOpenMenu }: { route: Route; onOpenMenu: () => void }) {
  const meta = pageMeta(route);
  const lastCrumb = meta.crumbs[meta.crumbs.length - 1];

  return (
    <header className="sticky top-0 z-20 border-b border-slate-200 bg-white/95 backdrop-blur supports-[backdrop-filter]:bg-white/80">
      <div className="flex h-16 items-center gap-3 px-4 sm:px-6 lg:px-8">
        <button
          type="button"
          onClick={onOpenMenu}
          className="rounded-lg p-2 text-slate-600 transition hover:bg-slate-100 hover:text-slate-900 lg:hidden"
        >
          <IconMenu size={20} />
          <span className="sr-only">Open navigation menu</span>
        </button>

        <nav aria-label="Breadcrumb" className="hidden min-w-0 sm:block">
          <ol className="flex min-w-0 items-center gap-1.5 text-sm">
            {meta.crumbs.map((crumb, index) => {
              const isLast = index === meta.crumbs.length - 1;
              const isLink = Boolean(crumb.path) && !isLast;
              return (
                <li key={crumb.label} className="flex min-w-0 items-center gap-1.5">
                  {index > 0 ? (
                    <IconChevronRight size={13} className="shrink-0 text-slate-300" />
                  ) : null}
                  {isLink ? (
                    <a
                      href={`#${crumb.path}`}
                      className="truncate text-slate-500 transition hover:text-civic-700"
                    >
                      {crumb.label}
                    </a>
                  ) : (
                    <span
                      className={cn(
                        'truncate',
                        isLast ? 'font-semibold text-slate-900' : 'text-slate-500',
                      )}
                      aria-current={isLast ? 'page' : undefined}
                    >
                      {crumb.label}
                    </span>
                  )}
                </li>
              );
            })}
          </ol>
        </nav>

        <p className="truncate text-sm font-semibold text-slate-900 sm:hidden">
          {lastCrumb?.label ?? meta.title}
        </p>

        <div className="ml-auto flex items-center gap-3">
          <AccountMenu />
        </div>
      </div>
    </header>
  );
}
