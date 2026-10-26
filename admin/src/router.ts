import { useEffect, useState } from 'react';

export type Route =
  | { page: 'overview' }
  | { page: 'reports' }
  | { page: 'report'; id: string }
  | { page: 'map'; select?: string }
  | { page: 'activity' }
  | { page: 'settings' }
  | { page: 'admin' }
  | { page: 'not-found'; path: string };

export function parseHash(hash: string): Route {
  const raw = hash.replace(/^#/, '');
  const normalized = raw.startsWith('/') ? raw : `/${raw}`;
  const [pathname, search] = normalized.split('?');
  const params = new URLSearchParams(search ?? '');
  const segments = pathname.split('/').filter(Boolean);

  if (segments.length === 0) return { page: 'overview' };

  switch (segments[0]) {
    case 'reports':
      if (segments.length === 1) return { page: 'reports' };
      if (segments.length === 2) return { page: 'report', id: decodeURIComponent(segments[1]) };
      break;
    case 'map':
      return { page: 'map', select: params.get('sel') ?? undefined };
    case 'activity':
      return { page: 'activity' };
    case 'settings':
      return { page: 'settings' };
    case 'admin':
      return { page: 'admin' };
    default:
      break;
  }

  return { page: 'not-found', path: pathname };
}

export function navigate(path: string): void {
  const next = path.startsWith('#') ? path : `#${path.startsWith('/') ? path : `/${path}`}`;
  if (window.location.hash === next) {
    window.dispatchEvent(new HashChangeEvent('hashchange'));
    return;
  }
  window.location.hash = next;
}

export function useRoute(): Route {
  const [route, setRoute] = useState<Route>(() => parseHash(window.location.hash));

  useEffect(() => {
    const onChange = () => setRoute(parseHash(window.location.hash));
    window.addEventListener('hashchange', onChange);
    return () => window.removeEventListener('hashchange', onChange);
  }, []);

  return route;
}

export function routeKey(route: Route): string {
  switch (route.page) {
    case 'report':
      return `report:${route.id}`;
    case 'map':
      return `map:${route.select ?? ''}`;
    case 'not-found':
      return `not-found:${route.path}`;
    default:
      return route.page;
  }
}
