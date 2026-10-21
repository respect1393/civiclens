import { useMemo, useState } from 'react';
import type { FormEvent, ReactNode } from 'react';
import type { Report, ReportStatus } from '../types';
import { useStore } from '../data/store';
import { CATEGORIES, STATUSES, STATUS_HEX, categoryLabel } from '../data/catalog';
import { formatDateTime, relativeTime } from '../lib/format';
import {
  buttonPrimaryClass,
  buttonSecondaryClass,
  labelClass,
  selectClass,
  textareaClass,
} from '../lib/styles';
import { ReportPhoto } from '../components/reports/ReportPhoto';
import { EmptyState } from '../components/ui/EmptyState';
import {
  IconAlert,
  IconArrowLeft,
  IconChevronDown,
  IconMap,
  IconNote,
  IconPhoto,
  IconPin,
} from '../components/ui/Icon';
import { PageHeader } from '../components/ui/PageHeader';
import { Panel } from '../components/ui/Panel';
import { StatusBadge } from '../components/ui/StatusBadge';

function InfoRow({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex flex-col gap-0.5 border-b border-slate-100 py-2.5 last:border-0 sm:flex-row sm:items-baseline sm:gap-4">
      <dt className="w-40 shrink-0 text-xs font-semibold tracking-wide text-slate-500 uppercase">
        {label}
      </dt>
      <dd className="min-w-0 text-sm text-slate-800">{children}</dd>
    </div>
  );
}

function ReportUpdateForm({
  report,
  authorName,
  onStatusChange,
  onNote,
}: {
  report: Report;
  authorName: string;
  onStatusChange: (status: ReportStatus) => Promise<void>;
  onNote: (body: string) => Promise<void>;
}) {
  // A pending status of `null` means "no change": the control shows the
  // report's current status until the administrator picks a different one. This
  // avoids mirroring the report status in state and never remounts mid-submit.
  const [pendingStatus, setPendingStatus] = useState<ReportStatus | null>(null);
  const [note, setNote] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [feedback, setFeedback] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const effectiveStatus = pendingStatus ?? report.status;
  const statusChanged = effectiveStatus !== report.status;
  const trimmedNote = note.trim();

  const handleSubmit = async (event: FormEvent) => {
    event.preventDefault();
    if (submitting) return;
    if (!statusChanged && trimmedNote.length === 0) {
      setError('Change the status, write an administrative note, or both.');
      return;
    }

    setSubmitting(true);
    setError(null);
    setFeedback(null);
    try {
      if (statusChanged) await onStatusChange(effectiveStatus);
      if (trimmedNote.length > 0) await onNote(trimmedNote);
      setNote('');
      setPendingStatus(null);
      setFeedback('Saved to the CivicLens backend.');
    } catch (submitError) {
      setError(
        submitError instanceof Error
          ? submitError.message
          : 'The change could not be saved. Please try again.',
      );
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Panel title="Update this report" description="Changes are saved to the backend">
      <form onSubmit={handleSubmit} noValidate>
        <div className="mb-4">
          <label htmlFor="detail-status" className={labelClass}>
            Status
          </label>
          <div className="relative">
            <select
              id="detail-status"
              value={effectiveStatus}
              onChange={(event) => setPendingStatus(event.target.value as ReportStatus)}
              className={selectClass}
              disabled={submitting}
            >
              {STATUSES.map((item) => (
                <option key={item} value={item}>
                  {item}
                </option>
              ))}
            </select>
            <IconChevronDown
              size={16}
              className="pointer-events-none absolute top-1/2 right-3 -translate-y-1/2 text-slate-400"
            />
          </div>
          {statusChanged ? (
            <p className="mt-1.5 text-xs text-amber-700">
              Status will change from {report.status} to {effectiveStatus}.
            </p>
          ) : (
            <p className="mt-1.5 text-xs text-slate-400">Current status: {report.status}</p>
          )}
        </div>

        <div className="mb-4">
          <label htmlFor="detail-note" className={labelClass}>
            Administrative note
          </label>
          <textarea
            id="detail-note"
            value={note}
            onChange={(event) => setNote(event.target.value)}
            placeholder="Add context for other administrators…"
            className={textareaClass}
            rows={4}
            disabled={submitting}
          />
          <p className="mt-1.5 text-xs text-slate-400">Saved as {authorName}.</p>
        </div>

        {error ? (
          <p role="alert" className="mb-3 rounded-lg bg-rose-50 px-3 py-2 text-xs text-rose-700">
            {error}
          </p>
        ) : null}
        {feedback ? (
          <p
            role="status"
            className="mb-3 rounded-lg bg-emerald-50 px-3 py-2 text-xs leading-relaxed text-emerald-800"
          >
            {feedback}
          </p>
        ) : null}

        <button type="submit" disabled={submitting} className={`${buttonPrimaryClass} w-full`}>
          {submitting ? 'Saving…' : 'Save changes'}
        </button>
      </form>
    </Panel>
  );
}

export function ReportDetailPage({ reportId }: { reportId: string }) {
  const { getReport, setStatus, addNote, profile } = useStore();
  const report = getReport(reportId);

  const history = useMemo(() => {
    if (!report) return [];
    return [...report.history].sort((a, b) => b.changedAt.localeCompare(a.changedAt));
  }, [report]);

  const notes = useMemo(() => {
    if (!report) return [];
    return [...report.notes].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }, [report]);

  if (!report) {
    return (
      <div className="rounded-xl border border-slate-200 bg-white shadow-sm">
        <EmptyState
          title="Report not found"
          description={`No report with the ID ${reportId} was returned by the backend. It may have been deleted.`}
          icon={<IconAlert size={22} />}
          action={
            <a href="#/reports" className={buttonSecondaryClass}>
              Back to reports
            </a>
          }
        />
      </div>
    );
  }

  const coordinates = report.location.coordinates;
  const submittedBy = report.reporterName
    ? `submitted ${formatDateTime(report.submittedAt)} by ${report.reporterName}`
    : `submitted ${formatDateTime(report.submittedAt)}`;

  return (
    <>
      <a
        href="#/reports"
        className="mb-4 inline-flex items-center gap-1.5 text-sm font-medium text-slate-500 transition hover:text-civic-700"
      >
        <IconArrowLeft size={16} />
        Back to all reports
      </a>

      <PageHeader
        title={report.title}
        description={`${report.id} · ${submittedBy}`}
        meta={<StatusBadge status={report.status} />}
        actions={
          <a href={`#/map?sel=${report.id}`} className={buttonSecondaryClass}>
            <IconMap size={16} />
            View on map
          </a>
        }
      />

      <div className="grid grid-cols-1 gap-5 lg:grid-cols-3">
        <div className="space-y-5 lg:col-span-2">
          <Panel title="Description" description="As submitted through the reporting flow">
            <p className="text-sm leading-relaxed text-slate-700">{report.description}</p>
          </Panel>

          <Panel title="Report information" description="Recorded details for this report">
            <dl>
              <InfoRow label="Report ID">
                <span className="font-mono font-semibold">{report.id}</span>
              </InfoRow>
              <InfoRow label="Category">
                <span className="inline-flex items-center gap-2">
                  <span
                    className="size-2 rounded-full"
                    style={{
                      backgroundColor:
                        CATEGORIES.find((item) => item.id === report.categoryId)?.color,
                    }}
                    aria-hidden="true"
                  />
                  {categoryLabel(report.categoryId)}
                </span>
              </InfoRow>
              <InfoRow label="Status">
                <StatusBadge status={report.status} size="sm" />
              </InfoRow>
              <InfoRow label="Reporter">
                {report.reporterName ? (
                  <span>
                    {report.reporterName}
                    {report.reporterEmail ? (
                      <span className="block text-xs text-slate-500">{report.reporterEmail}</span>
                    ) : null}
                  </span>
                ) : (
                  <span className="text-slate-400">Not available</span>
                )}
              </InfoRow>
              <InfoRow label="Submitted">{formatDateTime(report.submittedAt)}</InfoRow>
              <InfoRow label="Last updated">
                {formatDateTime(report.updatedAt)}{' '}
                <span className="text-slate-400">({relativeTime(report.updatedAt)})</span>
              </InfoRow>
              <InfoRow label="Reported location">
                <span className="block">{report.location.address}</span>
                <span className="block text-xs text-slate-500">{report.location.area}</span>
              </InfoRow>
              <InfoRow label="Landmark">
                {report.location.landmark ?? (
                  <span className="text-slate-400">No landmark provided</span>
                )}
              </InfoRow>
              <InfoRow label="Coordinates">
                {coordinates ? (
                  <span className="font-mono text-xs">
                    {coordinates.lat.toFixed(4)}, {coordinates.lng.toFixed(4)}
                  </span>
                ) : (
                  <span className="text-slate-400">Not provided for this report</span>
                )}
              </InfoRow>
              <InfoRow label="Priority">
                <span className="text-slate-400">Not tracked by the backend</span>
              </InfoRow>
              <InfoRow label="Assigned to">
                <span className="text-slate-400">Assignment is not supported</span>
              </InfoRow>
            </dl>
          </Panel>

          <Panel
            title="Photo evidence"
            description={
              report.hasPhoto ? 'Attached by the reporter' : 'No photo attached to this report'
            }
            bodyClassName="p-4 sm:p-5"
          >
            {report.hasPhoto ? (
              <ReportPhoto key={report.id} reportId={report.id} />
            ) : (
              <div className="flex flex-col items-center justify-center gap-2 rounded-lg border border-dashed border-slate-300 bg-slate-50 px-4 py-8 text-center">
                <span className="flex size-10 items-center justify-center rounded-full bg-white text-slate-400 shadow-sm">
                  <IconPhoto size={20} />
                </span>
                <p className="text-sm font-semibold text-slate-600">No photo attached</p>
                <p className="max-w-md text-xs leading-relaxed text-slate-500">
                  The reporter did not attach a photo to this report.
                </p>
              </div>
            )}
          </Panel>

          <Panel
            title="Administrative notes"
            description={`${notes.length} note${notes.length === 1 ? '' : 's'} on this report`}
          >
            {notes.length === 0 ? (
              <p className="text-sm text-slate-500">
                No administrative notes yet. Use the form on this page to add the first note.
              </p>
            ) : (
              <ul className="space-y-3">
                {notes.map((item) => (
                  <li
                    key={item.id}
                    className="rounded-lg border border-slate-200 bg-slate-50/70 p-3"
                  >
                    <div className="mb-1 flex flex-wrap items-center justify-between gap-2">
                      <span className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-700">
                        <IconNote size={14} className="text-slate-400" />
                        {item.author}
                      </span>
                      <span
                        className="text-xs text-slate-400"
                        title={formatDateTime(item.createdAt)}
                      >
                        {relativeTime(item.createdAt)}
                      </span>
                    </div>
                    <p className="text-sm leading-relaxed text-slate-700">{item.body}</p>
                  </li>
                ))}
              </ul>
            )}
          </Panel>
        </div>

        <div className="space-y-5">
          <ReportUpdateForm
            key={report.id}
            report={report}
            authorName={profile.name}
            onStatusChange={(status) => setStatus(report.id, status)}
            onNote={(body) => addNote(report.id, body)}
          />

          <Panel title="Status history" description="Recorded transitions for this report">
            {history.length === 0 ? (
              <p className="text-sm text-slate-500">
                No status changes have been recorded for this report.
              </p>
            ) : (
              <ol className="relative space-y-4 pl-1">
                {history.map((entry, index) => {
                  const isLast = index === history.length - 1;
                  return (
                    <li key={entry.id} className="relative flex gap-3">
                      {!isLast ? (
                        <span
                          className="absolute top-5 bottom-[-1rem] left-[7px] w-px bg-slate-200"
                          aria-hidden="true"
                        />
                      ) : null}
                      <span
                        className="relative z-10 mt-1 size-[15px] shrink-0 rounded-full border-2 border-white shadow-sm"
                        style={{ backgroundColor: STATUS_HEX[entry.status] }}
                        aria-hidden="true"
                      />
                      <div className="min-w-0 flex-1">
                        <p className="text-sm font-semibold text-slate-800">
                          {entry.previousStatus
                            ? `${entry.previousStatus} → ${entry.status}`
                            : entry.status}
                        </p>
                        <p className="text-xs text-slate-500">
                          <time dateTime={entry.changedAt} title={formatDateTime(entry.changedAt)}>
                            {relativeTime(entry.changedAt)}
                          </time>
                        </p>
                      </div>
                    </li>
                  );
                })}
              </ol>
            )}
          </Panel>

          <Panel title="Location" description="Reported area">
            <div className="flex items-start gap-3">
              <span className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-civic-50 text-civic-700">
                <IconPin size={18} />
              </span>
              <div className="min-w-0">
                <p className="text-sm font-semibold text-slate-800">{report.location.area}</p>
                <p className="text-sm text-slate-600">{report.location.address}</p>
                {report.location.landmark ? (
                  <p className="mt-0.5 text-xs text-slate-500">
                    Landmark: {report.location.landmark}
                  </p>
                ) : null}
                {coordinates ? (
                  <p className="mt-1 font-mono text-xs text-slate-400">
                    {coordinates.lat.toFixed(4)}, {coordinates.lng.toFixed(4)}
                  </p>
                ) : null}
                <a
                  href={`#/map?sel=${report.id}`}
                  className="mt-3 inline-flex items-center gap-1.5 text-xs font-semibold text-civic-700 hover:underline"
                >
                  <IconMap size={14} />
                  Open in map
                </a>
              </div>
            </div>
          </Panel>
        </div>
      </div>
    </>
  );
}
