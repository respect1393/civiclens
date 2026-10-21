import type { Route } from '../router';

export interface Crumb {
  label: string;
  path?: string;
}

export interface PageMeta {
  title: string;
  crumbs: Crumb[];
}

export function pageMeta(route: Route): PageMeta {
  switch (route.page) {
    case 'overview':
      return { title: 'Overview', crumbs: [{ label: 'Overview' }] };
    case 'reports':
      return {
        title: 'Reports',
        crumbs: [{ label: 'Overview', path: '/' }, { label: 'Reports' }],
      };
    case 'report':
      return {
        title: route.id,
        crumbs: [
          { label: 'Overview', path: '/' },
          { label: 'Reports', path: '/reports' },
          { label: route.id },
        ],
      };
    case 'map':
      return {
        title: 'Reports Map',
        crumbs: [{ label: 'Overview', path: '/' }, { label: 'Reports Map' }],
      };
    case 'activity':
      return {
        title: 'Activity',
        crumbs: [{ label: 'Overview', path: '/' }, { label: 'Activity' }],
      };
    case 'settings':
      return {
        title: 'Settings',
        crumbs: [{ label: 'Overview', path: '/' }, { label: 'Settings' }],
      };
    default:
      return { title: 'Page not found', crumbs: [{ label: 'Page not found' }] };
  }
}
