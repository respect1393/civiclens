import type { ReactNode } from 'react';
import { cn } from '../../lib/cn';

export function Panel({
  title,
  description,
  action,
  children,
  className,
  bodyClassName,
}: {
  title?: ReactNode;
  description?: ReactNode;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
  bodyClassName?: string;
}) {
  const hasHeader = title !== undefined || action !== undefined;
  return (
    <section className={cn('rounded-xl border border-slate-200 bg-white shadow-sm', className)}>
      {hasHeader ? (
        <header className="flex flex-wrap items-start justify-between gap-3 border-b border-slate-200 px-4 py-3.5 sm:px-5">
          <div className="min-w-0">
            {title ? (
              <h2 className="text-sm font-semibold text-slate-900">{title}</h2>
            ) : null}
            {description ? (
              <p className="mt-0.5 text-xs text-slate-500">{description}</p>
            ) : null}
          </div>
          {action ? <div className="shrink-0">{action}</div> : null}
        </header>
      ) : null}
      <div className={cn('p-4 sm:p-5', bodyClassName)}>{children}</div>
    </section>
  );
}
