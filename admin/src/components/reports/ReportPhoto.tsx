import { useEffect, useState } from 'react';
import { fetchReportPhoto } from '../../api/reports';
import { IconPhoto } from '../ui/Icon';

type PhotoState =
  | { status: 'loading' }
  | { status: 'ready'; url: string }
  | { status: 'error'; message: string };

/**
 * Loads a report's evidence image with an authenticated request. The backend
 * requires the session token, so the image cannot be fetched with a plain
 * <img src>; it is downloaded as a Blob and exposed through an object URL.
 */
export function ReportPhoto({ reportId }: { reportId: string }) {
  const [state, setState] = useState<PhotoState>({ status: 'loading' });

  useEffect(() => {
    const controller = new AbortController();
    let objectUrl: string | null = null;

    fetchReportPhoto(reportId, controller.signal).then(
      (blob) => {
        if (controller.signal.aborted) return;
        objectUrl = URL.createObjectURL(blob);
        setState({ status: 'ready', url: objectUrl });
      },
      () => {
        if (controller.signal.aborted) return;
        setState({ status: 'error', message: 'The photo could not be loaded.' });
      },
    );

    return () => {
      controller.abort();
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [reportId]);

  if (state.status === 'loading') {
    return (
      <div className="flex h-56 items-center justify-center rounded-lg border border-slate-200 bg-slate-50">
        <span className="text-xs text-slate-400" role="status">
          Loading photo…
        </span>
      </div>
    );
  }

  if (state.status === 'error') {
    return (
      <div className="flex flex-col items-center justify-center gap-2 rounded-lg border border-dashed border-slate-300 bg-slate-50 px-4 py-8 text-center">
        <IconPhoto size={20} className="text-slate-400" />
        <p className="text-sm font-semibold text-slate-600">{state.message}</p>
        <p className="max-w-md text-xs text-slate-500">
          The report has an attached photo, but it could not be retrieved from the backend.
        </p>
      </div>
    );
  }

  return (
    <img
      src={state.url}
      alt={`Photo evidence for report ${reportId}`}
      className="max-h-[28rem] w-full rounded-lg border border-slate-200 object-contain"
    />
  );
}
