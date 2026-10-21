const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

const relativeFormatter = new Intl.RelativeTimeFormat('en', { numeric: 'auto' });

const dateTimeFormatter = new Intl.DateTimeFormat('en', {
  day: 'numeric',
  month: 'short',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});

const dateFormatter = new Intl.DateTimeFormat('en', {
  day: 'numeric',
  month: 'short',
  year: 'numeric',
});

export function formatDateTime(iso: string): string {
  return dateTimeFormatter.format(new Date(iso));
}

export function formatDate(iso: string): string {
  return dateFormatter.format(new Date(iso));
}

export function relativeTime(iso: string): string {
  const delta = Date.now() - new Date(iso).getTime();
  const abs = Math.abs(delta);
  if (abs < MINUTE) return 'just now';
  if (abs < HOUR) return relativeFormatter.format(-Math.round(abs / MINUTE), 'minute');
  if (abs < DAY) return relativeFormatter.format(-Math.round(abs / HOUR), 'hour');
  if (abs < 7 * DAY) return relativeFormatter.format(-Math.round(abs / DAY), 'day');
  return formatDate(iso);
}

export function dayLabel(iso: string): string {
  const date = new Date(iso);
  const startOfToday = new Date();
  startOfToday.setHours(0, 0, 0, 0);
  const diffDays = Math.round((startOfToday.getTime() - date.getTime()) / DAY);
  if (diffDays <= 0) return 'Today';
  if (diffDays === 1) return 'Yesterday';
  return formatDate(iso);
}

export function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '??';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

