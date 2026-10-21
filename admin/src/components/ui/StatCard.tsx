import type { ReactNode } from 'react';
import { cn } from '../../lib/cn';

const ACCENTS = {
  civic: 'bg-civic-50 text-civic-700',
  amber: 'bg-amber-50 text-amber-700',
  violet: 'bg-violet-50 text-violet-700',
  emerald: 'bg-emerald-50 text-emerald-700',
  slate: 'bg-slate-100 text-slate-600',
} as const;

export function StatCard({
  label,
  value,
  hint,
  icon,
  accent = 'civic',
  meta,
}: {
  label: string;
  value: number | string;
  hint: string;
  icon: ReactNode;
  accent?: keyof typeof ACCENTS;
  meta?: ReactNode;
}) {
  return (
    <article className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-[11px] font-bold tracking-wider text-slate-500 uppercase">
            {label}
          </p>
          <p className="mt-2 text-3xl leading-none font-bold tracking-tight text-slate-900">
            {value}
          </p>
        </div>
        <span
          className={cn(
            'flex size-10 shrink-0 items-center justify-center rounded-lg',
            ACCENTS[accent],
          )}
        >
          {icon}
        </span>
      </div>
      <p className="mt-3 text-xs leading-relaxed text-slate-500">{hint}</p>
      {meta ? <div className="mt-2">{meta}</div> : null}
    </article>
  );
}
