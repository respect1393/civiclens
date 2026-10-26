# CIVICLENS mobile — technical design

Companion to [../README.md](../README.md). Covers architecture, data flow and
the engineering decisions behind the server-backed citizen app.

## Goals

- Give a citizen a trustworthy end-to-end loop: **see a problem → report it →
  track its status → see what changed**.
- Keep every promise the UI makes honest: a report is shown only after the
  backend accepts it, and no stale or invented data is ever displayed.
- Keep transport, storage and parsing concerns separated so the backend can
  evolve without touching the screens.

## Architecture

```
┌────────────────────────── widget tree ──────────────────────────┐
│  main.dart → AuthScope (InheritedNotifier) → AuthGate            │
│                 ├── LaunchPlaceholder (checking)*                │
│                 ├── LoginScreen / RegisterScreen (signed out)    │
│                 └── HomeScreen (signed in)                       │
│                        └── ReportScope (InheritedNotifier)       │
│                              ├── MyReportsScreen / Details       │
│                              └── ReportIssueScreen               │
└──────────────────────────────┬──────────────────────────────────┘
                               │ ReportScope.of(context)
                    ┌──────────▼──────────┐        ┌────────────────────┐
                    │  ReportRepository   │        │   AuthRepository   │
                    │  ChangeNotifier     │        │   ChangeNotifier   │
                    └──────────┬──────────┘        └─────────┬──────────┘
                               │                             │ AuthService / SessionStore
              ┌────────────────┼────────────────┐            │
              │                │                │  ┌─────────▼──────────┐
   ┌──────────▼───────┐ ┌──────▼─────────┐      │  │  HttpAuthService   │
   │ HttpReportApiSvc │ │  ReportStore   │      │  │  SecureSessionStore│
   │ (create/list/...)│ │ (image cache)  │      │  └─────────┬──────────┘
   └────────┬─────────┘ └────────────────┘      │            │
            └──────────────┬───────────────────┘             │
                    ┌───────▼────────┐                       │
                    │   ApiClient    │◀──────────────────────┘
                    │ json + bytes   │
                    └───────┬────────┘
                    ┌───────▼────────────┐
                    │  CIVICLENS backend │
                    │  /api/auth/*       │
                    │  /api/reports/*    │
                    └────────────────────┘
```
* `LaunchPlaceholder` is normally never painted: `main()` restores the session
  before the first frame (see [Session handling decisions](#session-handling-decisions)).

The backend is the single source of truth. `ReportRepository` holds an
in-memory list of the server's reports; `ReportStore` keeps only a local cache
of the bytes the citizen attached, so a chosen image renders instantly. There
is no local report database.

### Layers

| Layer | File | Responsibility |
| --- | --- | --- |
| Model | `lib/models/civic_report.dart` | `CivicReport`, `ReportStatus`, `ReportOrigin`, `StatusEvent`; JSON round-trip |
| Model | `lib/models/auth_user.dart`, `auth_session.dart` | Signed-in citizen profile and token |
| Transport | `lib/services/api_client.dart` | JSON + byte HTTP, base URL, bearer token, timeouts, status → failure mapping, 401 hook |
| Report API | `lib/services/report_api_service.dart` | Create/list/photo/delete requests, category and status mapping, payload shaping |
| Auth API | `lib/services/auth_service.dart` | Register / login |
| Image cache | `lib/services/report_store.dart` | Store captured photo bytes on disk for instant display |
| Profile store | `lib/services/profile_store.dart` | Optional device-local profile picture |
| State | `lib/state/report_repository.dart` | In-memory server-backed list; `load` / `submitReport` / `deleteReport` / `resolveReportImage` |
| State | `lib/state/auth_repository.dart` | Auth state machine; owns the token |
| Scope | `lib/state/report_scope.dart`, `auth_scope.dart` | Expose repositories to the tree (`of` / `read`) |
| Config | `lib/config/api_config.dart` | Base-URL resolution (`--dart-define` → platform default) |
| Presentation | `lib/screens/*`, `lib/widgets/*` | Build UI from repository state only |

The screens never touch the file system or the network directly. They call
repository methods and listen for changes, which means a single source of truth
backs Home, My Reports and Profile simultaneously.

## Data model

```dart
class CivicReport {
  String id;               // server Prisma id for fetched reports; CL-… for a
                           // just-created local shape before the server id wins
  String category;         // friendly label, mapped to/from the backend enum
  String title;
  String description;
  String? photoFileName;   // local cache file name, never base64
  String locationLabel;    // place/address name chosen by the citizen
  String? landmark;        // optional extra directions, null when left blank
  double latitude;
  double longitude;
  DateTime createdAt;
  ReportStatus status;
  List<StatusEvent> statusHistory;
  String? adminNotes;
  bool isSample;
  ReportOrigin origin;     // local (device only) or server (accepted by backend)
  String? serverId;        // backend id once submitted, else null
  String? serverPhotoPath; // backend photo reference, separate from photoFileName
}
```

- `civicReportFromApiJson` marks every fetched report `ReportOrigin.server`,
  keeps the server's `photoPath` in `serverPhotoPath`, and does **not** parse
  `statusHistory` — the app never fabricates a history it does not have, so the
  details screen shows an explicit "no status updates" state until the backend
  provides one.
- `CivicReport.isSample` and `adminNotes` are retained on the model for
  back-compatibility but are not used by the server-backed flow.
- `ReportStatus` is a closed enum with a display `label`. `pipeline` is the
  linear sequence used by the progress indicator; `Needs More Information` is a
  side branch and is excluded from it.
- `hasCoordinates` treats `0, 0` (Null Island) and out-of-range values as "no
  reporting point", so an older entry without coordinates is never drawn as a
  real address.

## Report flow

`ReportRepository` (`lib/state/report_repository.dart`) exposes one method per
user action; each maps to exactly one backend request and updates the in-memory
list only after the server confirms.

```
screen ──> repository.load()
              ├── GET /api/reports (bearer token)
              ├── on success: replace list, clear error
              ├── on failure: keep previous server list, set lastError
              └── notifyListeners()            ← UI rebuilds

screen ──> repository.submitReport(...)
              ├── POST /api/reports            → on failure: rethrow (UI explains)
              ├── cache photo bytes locally    (instant display)
              ├── POST /api/reports/:id/photo  → on failure: leave serverPhotoPath null
              ├── insert returned report
              └── notifyListeners()

screen ──> repository.deleteReport(id)
              ├── DELETE /api/reports/:id      → on failure: rethrow, list unchanged
              ├── remove locally, delete cached photo if unreferenced
              └── notifyListeners()
```

Key guarantees:

- **No optimistic report creation.** Nothing is added to the list before
  `POST /api/reports` returns 2xx, so a failed submission is never shown as
  saved.
- **A photo failure is not a report failure.** The report already exists on the
  server; a failed upload simply leaves `serverPhotoPath` null so the UI can say
  the evidence is missing rather than pretend it uploaded.
- **Delete is server-first.** The list is only updated after a 2xx `DELETE`, so
  the UI never claims a still-existing report is gone.
- **My Reports fetches on demand.** The screen starts a retrieval on first
  `didChangeDependencies` when the auth status is `authenticated` (guarded so it
  runs once), and again on pull-to-refresh.

`ReportScope` is an `InheritedNotifier`, so `notifyListeners()` rebuilds Home,
My Reports and Profile in the same frame — creating or deleting a report updates
the interface everywhere, including the Home summary counts.

## Image handling

The backend is the durable home of report photos.

1. **Capture → cache.** `submitReport` writes the attached bytes to
  `<app documents>/civiclens/report_images/<report-id>.<ext>` via `ReportStore`
  and references them by file name only.
- **Upload.** The same bytes are uploaded with
  `POST /api/reports/:id/photo`; the server's content-addressed `photoPath`
  comes back and is stored in `serverPhotoPath`.
- **Display.** `resolveReportImage(report)` returns the cached bytes first
  (instant, offline), then falls back to the authenticated
  `GET /api/reports/:id/photo` for reports fetched from the backend — including
  reports created on another device. A missing image resolves to null and the UI
  shows a placeholder instead of a broken image.

The optional profile picture follows the same shape under `profile_images/`,
with a tiny reference document (`profile.json`) holding only the file name. It
stays on the device and is never uploaded.

## Authentication

Citizen accounts use the backend's auth endpoints — there is no local or mocked
sign-in.

### State machine (`AuthRepository`)

```
checking ──restoreSession()──┬── no session / unusable token ──▶ unauthenticated
                             └── usable session ──────────────▶ authenticated
unauthenticated ──signIn/register success──▶ authenticated
authenticated ──signOut / 401 from a protected request──▶ unauthenticated
```

`main()` awaits `restoreSession()` before `runApp`, so startup resolves straight
to `LoginScreen` or `HomeScreen` while the Android launch screen covers the
read. `AuthGate` renders `checking` → `LaunchPlaceholder`, `unauthenticated` →
`LoginScreen`, `authenticated` → `HomeScreen`.

### Decisions

- **No `/api/auth/me`.** The backend has no "who am I" endpoint, so a saved
  token is validated locally (expiry) at launch and authoritatively by the server
  on each protected request. `restoreSession()` memoises its future, so rebuilds
  and hot restarts cannot race.
- **401 hook.** `ApiClient.onUnauthorized` fires only when a request that
  *carried* a token comes back `401`, so a rejected login (bad password) can
  never clear an unrelated session. It is wired to
  `AuthRepository.handleUnauthorized`.
- **`role` is not stored client-side.** The app performs no client-side
  authorization, so a persisted role could never grant anything.
- **No citizen-facing exception leaks server text.** `ApiClient` surfaces only a
  length-capped, single-line, developer-authored error string plus app-authored
  generic copy; response bodies, tokens and headers are never shown or logged.
- **State / district.** Plain strings server-side with no lookup endpoint. The
  state list is bundled in `lib/data/indian_states.dart`; the district is typed
  freely. No endpoint is invented for either.

## Outbound network usage

- `POST /api/auth/register`, `POST /api/auth/login`.
- For a signed-in citizen: `GET /api/reports`, `POST /api/reports`,
  `DELETE /api/reports/:id`, `POST /api/reports/:id/photo` and
  `GET /api/reports/:id/photo` against the CIVICLENS backend.
- OpenStreetMap raster tiles (`tile.openstreetmap.org`) in the location picker.
- OpenStreetMap Nominatim `/search` and `/reverse` for place labels.

Base URL resolution lives in `lib/config/api_config.dart`
(`--dart-define=API_BASE_URL` overrides the platform default). Plain HTTP is a
development convenience: Android permits cleartext only in the `debug`/`profile`
manifests, so release builds require HTTPS.

## UI states

Each surface handles loading, empty, success and error explicitly:

- **My Reports**: a loading view while the first fetch is in flight, an empty
  state with a "Report an Issue" action, and an error view with a "Try again"
  button. Pull-to-refresh re-requests the list.
- **Details**: a not-found state for a missing report id, and an explicit "no
  status updates" state when the server provides no history.
- **Submission**: inline validation (category, title, description, photo,
  location), a progress state on the submit button, a confirmation dialog only
  after the server accepts the report (carrying the server reference), and an
  error `SnackBar` on failure.
- **Delete**: a confirmation dialog, then a success snackbar only after the
  server confirms; a failure snackbar that says the report is still on the
  city's records.

## Testing strategy

| Level | Approach |
| --- | --- |
| Model | JSON round-trip, tolerant parsing, status labels, origin metadata |
| Store | Real temp directory: image save / resolve / delete; profile-picture reference |
| Transport | `MockClient` — request shape, status → failure mapping, safe error copy, 401 hook |
| Report API | `MockClient` — payload shape, category + status mapping, photo upload/fetch, delete, malformed responses |
| Auth state | Restore, expiry drop, sign-in/register, sign-out, re-entrancy guard |
| Repository | Server-backed load, submit (with photo upload and upload-failure path), delete, image resolution |
| Widget | `CivicLensApp(repository: …, auth: …)` with `FakeReportApiService` and in-memory auth/store doubles |

Measured constraints worth keeping in mind when writing tests:

1. **`FutureBuilder` must not receive a fresh `Future` on every rebuild** — it
   re-subscribes each build and schedules frames forever, which hangs
   `pumpAndSettle`. Affected widgets (`profile_screen.dart`,
   `report_thumbnail.dart`) cache their futures in state.
2. **`dart:io` operations started inside the Flutter test binding's `FakeAsync`
   zone never complete**, so widget-level disk calls would hang. Widget tests use
   in-memory doubles; real disk behaviour is covered by the store/repository
   unit tests.
3. **A `pumpAndSettle` timeout usually means a permanent animation, not a slow
   path.** Busy state must always be cleared on every exit path; a stuck
   `CircularProgressIndicator` is the usual cause.
4. **`DropdownButtonFormField` needs `isExpanded: true` here.** Without it the
   field sizes itself to the widest entry and overflows the form on a narrow
   screen.
5. **A `const []` returned from a fake breaks an in-place `sort`.** The
   repository sorts the fetched list, so test doubles must return a growable
   list (`<CivicReport>[]`), not a const one.

## Known limitations

- Reports live on the backend, so the app needs a reachable backend to sign in,
  fetch reports or submit; there is no offline queue.
- `dart:io` storage does not run on the web target, so the web build is
  unsupported.
- The backend is reached over plain HTTP while developing; release builds keep
  Android's cleartext block and require HTTPS.
- The optional profile picture is device-local only and does not follow the
  citizen to another device.
- The server-backed flow does not parse a report's status history, so the
  details screen shows an explicit empty-history state until the backend exposes
  one.

## Future work (not implemented)

- An authenticated administrator flow for the pipeline (the `admin/` dashboard).
- Surfacing server-side status history so details can show real transitions.
- Conflict handling for reports edited on two devices.
- Offline capture with a retry queue.

## System-level architecture (whole project)

This section describes the entire CIVICLENS deployment: the Flutter citizen app, the Express backend, the SQLite database, on-disk image storage, and the React admin dashboard. Nothing here changes application source code; it is a documentation snapshot of what is implemented.

### Component diagram

```
 ┌─────────────────┐        HTTPS/HTTP        ┌──────────────────────────┐
 │   Citizen app   │ ◄───────────────────────► │   CIVICLENS backend    │
 │  (Flutter, Dart)│                           │   (Express, TS)          │
 └────────┬────────┘                           └───────────┬─────────────┘
          │ /api/auth/*  /api/reports/*                    │
          │                                              │ prisma (SQLite)
 ┌────────▼────────┐                                      ▼
 │   OS keychain   │                               ┌─────────────┐
 │  (session token)│                               │   SQLite    │
 └─────────────────┘                               │   db        │
                                                   └──────┬──────┘
                                                          │ photoPath references
 ┌───────────────────────────────────────────────────────▼─────────┐
 │  Image storage (uploads/reports/<sha256>.<ext>)                  │
 │  content-addressed, atomic temp+rename, traversal-guarded       │
 └─────────────────────────────────────────────────────────────────┘

 ┌─────────────────┐        HTTPS/HTTP        ┌──────────────────────────┐
 │   Admin dashboard│ ◄───────────────────────► │   CIVICLENS backend    │
 │  (React, TS)    │    same /api/* routes    │   (shared)               │
 └─────────────────┘                           └──────────────────────────┘
```

### Data flows

**Citizen sign-in / registration**
1. Citizen submits email + password from `LoginScreen` / `RegisterScreen`.
2. `AuthService` → `POST /api/auth/register` or `POST /api/auth/login` (login passes through the fixed-window rate limiter: 10 attempts per IP per 15 minutes).
3. Backend validates with zod, hashes passwords with bcryptjs, issues an HS256 JWT (7-day expiry) signed with `JWT_SECRET`.
4. The app stores the token in the OS keychain / secure session store; `AuthRepository` restores it at launch (no `/api/auth/me` endpoint exists).

**Citizen files a report**
1. `ReportRepository.submitReport` → `POST /api/reports` (authenticated; state/district taken from the DB-backed session).
2. Backend validates payload with zod, inserts the row with the caller's `userId` and geographic info, returns the report.
3. Only on a 2xx is the report inserted into the in-memory list (no optimistic creation).
4. The chosen photo bytes are cached locally for instant display, then `POST /api/reports/:id/photo` uploads them raw (no multipart/base64).
5. The backend validates magic bytes (JPEG/PNG/WebP only), writes the file atomically under a sha256 content-addressed key, enforces the 5 MB cap, and records `photoPath`. Ownership is checked: only the report's author may attach.

**Citizen views / deletes reports**
- `GET /api/reports` returns a paginated envelope (`data`, `pagination`). Citizens see only reports matching their state (and district when set); administrators see all.
- `GET /api/reports/:id` returns one report; citizens are gated by the same state/district rule and never receive `adminNotes` or `statusHistory`. Administrators receive both.
- `DELETE /api/reports/:id` is owner-only; database deletion cascades to `StatusHistory` and `AdminNote`, then the image is removed only when no other report references it.

**Citizen views a report photo**
- `GET /api/reports/:id/photo` is authenticated, re-checked against the same visibility rule as the report itself, path-traversal guarded (`resolveWithin`), served with `Cache-Control: private`.

**Administrator actions**
- `PATCH /api/reports/:id/status` (admin-only) transitions status inside a Prisma transaction that also writes one `StatusHistory` row; re-asserting the current status is a no-op (no duplicate history).
- `POST /api/reports/:id/notes` (admin-only) creates an `AdminNote` attributed to the DB-loaded administrator id (never the request body), max 2000 chars.
- `GET /api/reports` / `:id` for administrators include `statusHistory` and `adminNotes`.

### Backend tech stack responsibilities

| Layer | Technology | Responsibility |
| --- | --- | --- |
| Framework | Express 5.3.0 | HTTP routing, middleware, JSON API |
| ORM / database | Prisma 7.10.1 + better-sqlite3 (SQLite) | Schema, queries, transactions, connection pool |
| Auth | bcryptjs + jsonwebtoken (HS256) | Password hashing, JWT issue/verify (7-day expiry) |
| Validation | zod | Request schemas for register, login, reports, status, notes |
| Security | helmet, cors | Headers, CORS |
| Image storage | custom `storage.ts` module | Magic-byte detection, content-addressed sha256 keys, atomic temp+rename write, traversal-safe path resolution, 5 MB limit |
| Dev runtime | tsx | Run TypeScript directly |
| Tests | vitest + supertest | Route-level tests for auth, reports, images, errors |

Route set (all under `/api`): `GET /health`; `POST /auth/register`, `POST /auth/login` (rate-limited); `GET /reports`, `POST /reports`, `GET /reports/:id`, `PATCH /reports/:id/status`, `POST /reports/:id/notes`, `POST /reports/:id/photo`, `GET /reports/:id/photo`, `DELETE /reports/:id`.

Database models (single SQLite file): `User`, `Report`, `StatusHistory`, `AdminNote`. Citizens register as `CITIZEN` only; `ADMIN` accounts are created out-of-band and carry no state/district, seeing every report.

### Admin dashboard implementation status

- Stack: React + Vite + TypeScript, hash-based routing.
- Auth: `SessionProvider` holding a JWT in `sessionStorage`; `StoreProvider` for report list state.
- Pages: `Login`, `Overview`, `Reports`, `ReportDetail`, `Activity`, `Map`, `Settings`.
- Components: `ReportsTable`, `ReportPhoto`, `StatusBadge`, `SubmissionChart`, `CategoryBars`, `StatusDonut`.
- API client (`api/client.ts`, `api/reports.ts`) calls the same backend `/api/*` routes with bearer auth.
- Types (`types.ts`): `ReportStatus` = Submitted | Under Review | In Progress | Resolved | Rejected; `CategoryId` = roads | streetlights | water | waste | drainage | safety. `priority?` and `assignee?` are present on the admin `Report` interface but are explicitly "Not supplied by the backend".
- The dashboard consumes backend endpoints that exist (report list, detail, status transition, notes). It is the authenticated administrator flow referenced in mobile "Future work"; no separate admin-only API surface is invented.

### Prototype limitations (explicit)

- Single SQLite database file on the backend host; no replication, failover, or managed database.
- Images live on the local filesystem under `backend/uploads` (or `UPLOAD_DIR`), not an object store; the storage module is designed so an object store could replace it without touching routes.
- Login rate limiting is in-memory per IP (fixed window); it resets on restart and is not shared across backend instances.
- JWT secret (`JWT_SECRET`, ≥32 chars) and `DATABASE_URL` must be set in the environment; no fallbacks.
- Plain HTTP is a development convenience; release Android builds require HTTPS (cleartext blocked).
- No `/api/auth/me` endpoint; tokens are validated locally at launch and authoritatively on each protected request.
- Mobile web target is unsupported (`dart:io` storage).
- No offline queue; reports require a reachable backend to sign in, fetch, or submit.
- `priority` and `assignee` fields exist only in the admin TypeScript types; the backend does not supply them.
- Admin `ADMIN` accounts are created out-of-band; there is no self-service admin registration.
