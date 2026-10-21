import type { SVGProps } from 'react';
import { cn } from '../../lib/cn';

export interface IconProps extends SVGProps<SVGSVGElement> {
  size?: number;
}

function IconBase({ size = 20, className, children, ...props }: IconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.75}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
      className={cn('shrink-0', className)}
      {...props}
    >
      {children}
    </svg>
  );
}

export function IconOverview(props: IconProps) {
  return (
    <IconBase {...props}>
      <rect x="3.5" y="3.5" width="7" height="7" rx="1.5" />
      <rect x="13.5" y="3.5" width="7" height="7" rx="1.5" />
      <rect x="3.5" y="13.5" width="7" height="7" rx="1.5" />
      <rect x="13.5" y="13.5" width="7" height="7" rx="1.5" />
    </IconBase>
  );
}

export function IconReports(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" />
      <path d="M14 3v5h5" />
      <path d="M9 13h6" />
      <path d="M9 17h4" />
    </IconBase>
  );
}

export function IconMap(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="M9 4 3 6.5v13L9 17l6 2.5 6-2.5v-13L15 6.5 9 4z" />
      <path d="M9 4v13" />
      <path d="M15 6.5v13" />
    </IconBase>
  );
}

export function IconActivity(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="M3 12h4l2.5 6.5L13.5 5l2.5 7h5" />
    </IconBase>
  );
}

export function IconSettings(props: IconProps) {
  return (
    <IconBase {...props}>
      <circle cx="12" cy="12" r="3" />
      <path d="M19.1 14.6a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-1.8-.3 1.6 1.6 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.2a1.6 1.6 0 0 0-1-1.4 1.6 1.6 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0 .3-1.8 1.6 1.6 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.2a1.6 1.6 0 0 0 1.4-1 1.6 1.6 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 1.8.3H9a1.6 1.6 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.2a1.6 1.6 0 0 0 1 1.4 1.6 1.6 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8V9a1.6 1.6 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.2a1.6 1.6 0 0 0-1.4 1z" />
    </IconBase>
  );
}

export function IconSearch(props: IconProps) {
  return (
    <IconBase {...props}>
      <circle cx="11" cy="11" r="7" />
      <path d="m20.5 20.5-4-4" />
    </IconBase>
  );
}

export function IconFilter(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="M4 5h16l-6.2 7.3V19l-3.6 1.8v-8.5L4 5z" />
    </IconBase>
  );
}

export function IconMenu(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="M4 7h16" />
      <path d="M4 12h16" />
      <path d="M4 17h16" />
    </IconBase>
  );
}

export function IconClose(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="m6 6 12 12" />
      <path d="M18 6 6 18" />
    </IconBase>
  );
}

export function IconChevronDown(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="m6 9.5 6 6 6-6" />
    </IconBase>
  );
}

export function IconChevronRight(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="m9.5 6 6 6-6 6" />
    </IconBase>
  );
}

export function IconArrowLeft(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="M19.5 12H5" />
      <path d="m11 6-6 6 6 6" />
    </IconBase>
  );
}

export function IconUser(props: IconProps) {
  return (
    <IconBase {...props}>
      <circle cx="12" cy="8.5" r="3.75" />
      <path d="M4.5 20.5c.7-3.6 3.9-5.8 7.5-5.8s6.8 2.2 7.5 5.8" />
    </IconBase>
  );
}

export function IconCheckCircle(props: IconProps) {
  return (
    <IconBase {...props}>
      <circle cx="12" cy="12" r="8.75" />
      <path d="m8.4 12.4 2.5 2.5 4.7-5.4" />
    </IconBase>
  );
}

export function IconClock(props: IconProps) {
  return (
    <IconBase {...props}>
      <circle cx="12" cy="12" r="8.75" />
      <path d="M12 7.2V12l3.2 1.9" />
    </IconBase>
  );
}

export function IconAlert(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="M12 4.4 2.9 19.6h18.2L12 4.4z" />
      <path d="M12 10.2v3.6" />
      <path d="M12 16.7h.01" />
    </IconBase>
  );
}

export function IconInfo(props: IconProps) {
  return (
    <IconBase {...props}>
      <circle cx="12" cy="12" r="8.75" />
      <path d="M12 11.2v5" />
      <path d="M12 8.2h.01" />
    </IconBase>
  );
}

export function IconPin(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="M12 21.2s6.8-6 6.8-10.7a6.8 6.8 0 1 0-13.6 0C5.2 15.2 12 21.2 12 21.2z" />
      <circle cx="12" cy="10.3" r="2.4" />
    </IconBase>
  );
}

export function IconNote(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="M4 20h4.2L19.4 8.8a2.1 2.1 0 0 0-3-3L5.2 17 4 20z" />
      <path d="m14.6 7.4 3 3" />
    </IconBase>
  );
}

export function IconRefresh(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="M3.6 12a8.4 8.4 0 0 1 14.3-6" />
      <path d="M20.4 12a8.4 8.4 0 0 1-14.3 6" />
      <path d="M18.4 2.8v3.6h-3.6" />
      <path d="M5.6 21.2v-3.6h3.6" />
    </IconBase>
  );
}

export function IconInbox(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="M6.2 4.5h11.6l3.2 8.2v5.1a1.7 1.7 0 0 1-1.7 1.7H4.7a1.7 1.7 0 0 1-1.7-1.7v-5.1L6.2 4.5z" />
      <path d="M2.7 13h5l1.4 2.6h5.8L16.3 13h5" />
    </IconBase>
  );
}

export function IconDatabase(props: IconProps) {
  return (
    <IconBase {...props}>
      <ellipse cx="12" cy="6.2" rx="7.8" ry="3" />
      <path d="M4.2 6.2v11.6c0 1.7 3.5 3 7.8 3s7.8-1.3 7.8-3V6.2" />
      <path d="M4.2 12c0 1.7 3.5 3 7.8 3s7.8-1.3 7.8-3" />
    </IconBase>
  );
}

export function IconLock(props: IconProps) {
  return (
    <IconBase {...props}>
      <rect x="4.5" y="10.5" width="15" height="9.8" rx="2" />
      <path d="M8.2 10.5V7.8a3.8 3.8 0 0 1 7.6 0v2.7" />
    </IconBase>
  );
}

export function IconLayers(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="m12 3.4 8.4 4.4-8.4 4.4L3.6 7.8 12 3.4z" />
      <path d="m3.6 12.4 8.4 4.4 8.4-4.4" />
      <path d="m3.6 16.6 8.4 4.4 8.4-4.4" />
    </IconBase>
  );
}



export function IconTrash(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="M4 7h16" />
      <path d="M9.6 7V5.6A1.6 1.6 0 0 1 11.2 4h1.6a1.6 1.6 0 0 1 1.6 1.6V7" />
      <path d="M6.6 7l.8 12a2 2 0 0 0 2 1.9h5.2a2 2 0 0 0 2-1.9l.8-12" />
    </IconBase>
  );
}


export function IconPhoto(props: IconProps) {
  return (
    <IconBase {...props}>
      <rect x="3.5" y="5" width="17" height="14" rx="2" />
      <circle cx="9" cy="10" r="1.6" />
      <path d="m4.5 17.5 4.6-4.4a2 2 0 0 1 2.8 0l6.6 6.4" />
    </IconBase>
  );
}

export function IconLogout(props: IconProps) {
  return (
    <IconBase {...props}>
      <path d="M9.5 20H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h3.5" />
      <path d="M15.5 16.5 20 12l-4.5-4.5" />
      <path d="M20 12H9" />
    </IconBase>
  );
}
