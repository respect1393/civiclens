import { useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { routeKey } from '../../router';
import type { Route } from '../../router';
import { Sidebar } from './Sidebar';
import { Topbar } from './Topbar';

export function AppShell({ route, children }: { route: Route; children: ReactNode }) {
  const [menuOpen, setMenuOpen] = useState(false);
  const mainRef = useRef<HTMLElement>(null);
  const currentKey = routeKey(route);

  useEffect(() => {
    const closeMenu = () => setMenuOpen(false);
    window.addEventListener('hashchange', closeMenu);
    return () => window.removeEventListener('hashchange', closeMenu);
  }, []);

  useEffect(() => {
    window.scrollTo({ top: 0 });
  }, [currentKey]);

  const focusMain = () => {
    mainRef.current?.focus();
    mainRef.current?.scrollIntoView();
  };

  return (
    <div className="min-h-screen bg-slate-50">
      <button
        type="button"
        onClick={focusMain}
        className="sr-only rounded-lg bg-civic-700 px-4 py-2 text-sm font-semibold text-white focus:not-sr-only focus:fixed focus:top-3 focus:left-3 focus:z-50"
      >
        Skip to main content
      </button>

      <Sidebar route={route} open={menuOpen} onClose={() => setMenuOpen(false)} />

      <div className="lg:pl-64">
        <Topbar route={route} onOpenMenu={() => setMenuOpen(true)} />

        <main
          ref={mainRef}
          tabIndex={-1}
          id="main-content"
          className="mx-auto w-full max-w-7xl px-4 py-6 outline-none sm:px-6 lg:px-8"
        >
          {children}
        </main>

        <footer className="mx-auto w-full max-w-7xl px-4 pt-2 pb-8 text-xs text-slate-400 sm:px-6 lg:px-8">
          CivicLens Admin · connected to the CivicLens backend API
        </footer>
      </div>
    </div>
  );
}
