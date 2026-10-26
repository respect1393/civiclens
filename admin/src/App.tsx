import { SessionProvider } from './auth/SessionProvider';
import { useSession } from './auth/sessionContext';
import { StoreProvider } from './data/StoreProvider';
import { useStore } from './data/store';
import { useRoute } from './router';
import type { Route } from './router';
import { AppShell } from './components/layout/AppShell';
import { EmptyState } from './components/ui/EmptyState';
import { IconAlert, IconRefresh } from './components/ui/Icon';
import { LoadingState } from './components/ui/LoadingState';
import { buttonPrimaryClass, buttonSecondaryClass } from './lib/styles';
import { ActivityPage } from './pages/ActivityPage';
import { AdminManagementPage } from './pages/AdminManagementPage';
import { LoginPage } from './pages/LoginPage';
import { MapPage } from './pages/MapPage';
import { OverviewPage } from './pages/OverviewPage';
import { ReportDetailPage } from './pages/ReportDetailPage';
import { ReportsPage } from './pages/ReportsPage';
import { SettingsPage } from './pages/SettingsPage';

function ErrorState({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <div className="rounded-xl border border-slate-200 bg-white shadow-sm">
      <EmptyState
        title="Reports could not be loaded"
        description={message}
        icon={<IconAlert size={22} />}
        action={
          <button type="button" onClick={onRetry} className={buttonPrimaryClass}>
            <IconRefresh size={16} />
            Retry
          </button>
        }
      />
    </div>
  );
}

function NotFoundPage() {
  return (
    <div className="rounded-xl border border-slate-200 bg-white shadow-sm">
      <EmptyState
        title="Page not found"
        description="This route does not exist in the CivicLens Admin dashboard."
        icon={<IconAlert size={22} />}
        action={
          <a href="#/" className={buttonSecondaryClass}>
            Go to overview
          </a>
        }
      />
    </div>
  );
}

function RouteView({ route }: { route: Route }) {
  const { loading, error, reload } = useStore();

  if (loading) {
    return <LoadingState rows={6} label="Loading reports from the CivicLens backend" />;
  }

  if (error) {
    return <ErrorState message={error} onRetry={reload} />;
  }

  switch (route.page) {
    case 'overview':
      return <OverviewPage />;
    case 'reports':
      return <ReportsPage />;
    case 'report':
      return <ReportDetailPage reportId={route.id} />;
    case 'map':
      return <MapPage selectedId={route.select} />;
    case 'activity':
      return <ActivityPage />;
    case 'settings':
      return <SettingsPage />;
    case 'admin':
      return <AdminManagementPage />;
    default:
      return <NotFoundPage />;
  }
}

function AuthenticatedApp() {
  const route = useRoute();

  return (
    <StoreProvider>
      <AppShell route={route}>
        <RouteView route={route} />
      </AppShell>
    </StoreProvider>
  );
}

function AuthGate() {
  const { session } = useSession();

  if (!session) {
    return <LoginPage />;
  }

  return <AuthenticatedApp />;
}

export default function App() {
  return (
    <SessionProvider>
      <AuthGate />
    </SessionProvider>
  );
}
