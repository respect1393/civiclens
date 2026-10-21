# CIVICLENS — mobile prototype

**Your City. Your Voice. Visible Change.**
Theme: Urban Inclusion & Infrastructure · Team GenEvo

CIVICLENS is a citizen-facing Flutter application for reporting civic problems
such as potholes, damaged streetlights, water-supply issues, waste accumulation
and damaged public infrastructure.

> **Prototype notice.** This is a hackathon prototype. When you are signed in,
> the municipal backend is the single source of truth: your reports and their
> photos live on the server, and the app reads them back from it. There is no
> city department behind the backend and no report is dispatched to a real
> authority. Citizen accounts and report submission are real HTTP calls to the
> local backend; plain HTTP is development-only and must never ship.

---

## What the app does

| Area | Behaviour |
| --- | --- |
| Accounts | Register / sign in against the backend (`/api/auth/*`); the JWT is stored in secure storage |
| Report an issue | Form with category, title, description, photo, map location and optional landmark |
| Submit | Creates the report on the backend, caches the photo locally for instant display, and uploads the photo to the backend |
| My Reports | Fetches the citizen's reports from the backend on open and on pull-to-refresh, with loading, empty and error states |
| Report details | Full description, photo (local cache or authenticated server fetch), location, coordinates, timestamp, report id and server status |
| Delete | Deletes the report on the backend after confirmation; the UI only removes it once the server confirms |
| Profile | Citizen identity and an optional device-local profile picture, plus sign out |
| Home | Summary counts (Saved / Active / Resolved) and recent reports, read live from the repository |
| Location picker | Map tiles from OpenStreetMap, place search and reverse geocoding via Nominatim |

The municipal backend is the single source of truth. The app keeps **no local
report database**: the list, the loading state, the empty state and every error
all come from the same backend request, so the screen can never show a stale or
invented report.

### Status pipeline

Server statuses map to the app's status as follows (see
`lib/services/report_api_service.dart`):

| Backend status | App status |
| --- | --- |
| `SUBMITTED` | `Reported` |
| `UNDER_REVIEW` | `Under Review` |
| `IN_PROGRESS` | `In Progress` |
| `RESOLVED` | `Resolved` |
| `REJECTED` | `Needs More Information` |
| anything else | `Reported` |

`REJECTED` is mapped onto `Needs More Information` because the Flutter model has
no dedicated rejected status; this is a deliberate, documented, lossy mapping.
The status history is never fabricated.

### Deliberately not implemented

- No background or automatic sync. A report is submitted once, when you press
  submit; older reports are never re-sent.
- The admin dashboard is **not** part of this app. It lives in `admin/` and is
  not connected to the mobile app.
- Explore and the map feed are still placeholders.
- No push notifications or offline queue.

---

## Requirements

| Tool | Version used |
| --- | --- |
| Flutter | 3.47.1 (stable) |
| Dart | 3.13.1 |
| `pubspec.yaml` constraint | `sdk: ^3.13.1` |

## Setup

```bash
cd mobile
flutter pub get
```

## Run the app

```bash
flutter run            # with a device or emulator attached
flutter run -d chrome  # web build is unsupported for storage, see limitations
```

The app needs the backend running to sign in, fetch reports or submit. A
backend already running on `http://localhost:3000` is the local default for
desktop; the Android emulator reaches it through `10.0.2.2`.

### Pointing the app at the backend

The API base URL is resolved at runtime by `lib/config/api_config.dart`; no
widget or service hardcodes a host.

| Where the app runs | Base URL | Notes |
| --- | --- | --- |
| Android emulator | `http://10.0.2.2:3000` | default; `10.0.2.2` is the emulator's alias for the host loopback |
| Flutter on the same machine as the backend | `http://127.0.0.1:3000` | default on desktop |
| Physical phone / any other host | `http://<LAPTOP_LAN_IP>:3000` | pass it explicitly |

Override the default for any platform with a `--dart-define`:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.42:3000
```

The phone and the laptop must be on the same network and the laptop firewall
must allow the port. The backend binds every interface (`app.listen(PORT)`), so
no backend change is needed for physical-device development.

> Plain HTTP is for local development only. Android only permits cleartext in
> the `debug` and `profile` manifests (`android:usesCleartextTraffic="true"`);
> release builds keep the platform default, so a production backend must be
> served over HTTPS. Certificate verification is never relaxed.

## Run the checks

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

## Tests

| File | Covers |
| --- | --- |
| `test/models/civic_report_test.dart` | Model round-trip, tolerant parsing, status mapping |
| `test/models/civic_report_origin_test.dart` | Local/server origin metadata and round-trip |
| `test/services/api_client_test.dart` | JSON and byte transport, status mapping, safe errors, 401 hook |
| `test/services/auth_service_test.dart` | Register/login request shape and status-code mapping |
| `test/services/report_api_service_test.dart` | Category/status mapping, create payload shape, photo upload/fetch, delete |
| `test/services/report_store_test.dart` | Real disk image save / resolve / delete |
| `test/services/profile_store_test.dart` | Profile-picture save / resolve / clear, reference-only document |
| `test/services/location_service_test.dart` | Location service behaviour |
| `test/services/place_search_service_test.dart` | Nominatim search/reverse parsing |
| `test/state/auth_repository_test.dart` | Restore, expiry drop, sign in/register, sign out, 401 |
| `test/state/report_repository_test.dart` | Server-backed load, submit (with photo upload), delete, image resolution |
| `test/screens/auth_flow_test.dart` | Login / register / sign-out flows |
| `test/screens/report_flow_test.dart` | Form validation, server-backed My Reports, details, delete |
| `test/screens/report_issue_screen_test.dart` | Location name / landmark handling and submission |
| `test/screens/report_delivery_test.dart` | Submission confirmation and failure messaging |
| `test/screens/my_reports_server_test.dart` | My Reports fetch / empty / error+retry / loading / signed-out / refresh / details |
| `test/screens/profile_screen_test.dart` | Profile identity, optional picture, sign out |
| `test/screens/location_picker_screen_test.dart` | Map selection, search, confirmation |
| `test/widgets/report_saved_dialog_test.dart` | Submission dialog content |
| `test/widgets/status_timeline_test.dart` | Status timeline rendering |
| `test/utils/report_format_test.dart` | Category icons, location/coordinate/date formatting |
| `test/widget_test.dart` | Home summary and navigation |
| `test/config/api_config_test.dart` | Base-URL resolution and `--dart-define` override |
| `test/helpers/*` | In-memory doubles for auth, reports, profile picture, image picker, location |

## Authentication

Citizen accounts use the backend's auth endpoints; there is no local or mocked
sign-in:

| Flow | Request | Success | Errors surfaced |
| --- | --- | --- | --- |
| Register | `POST /api/auth/register` `{name,email,password,state,district}` | `201 {user, token}` | `400 Invalid registration data` (per-field messages), `400 Email already registered` |
| Sign in | `POST /api/auth/login` `{email,password}` | `200 {user, token}` | `400 Invalid login data`, `401 Invalid credentials` |

- **Token storage.** The JWT and the profile are stored with secure storage.
- **Session restore.** `main()` awaits `restoreSession()` *before* `runApp`, so
  the first Flutter frame is already the signed-in app or the login screen.
  There is no `/api/auth/me`, so a saved token is validated locally (expiry) and
  authoritatively by the server on each protected request.
- **401 hook.** `ApiClient.onUnauthorized` fires only when a request that
  *carried* a token returns `401`, so a rejected login can never clear an
  unrelated session.
- **State / district.** Both are plain strings server-side; the state list is
  bundled (`lib/data/indian_states.dart`) and the district is typed by the
  citizen.

Auth code lives in `lib/services/{api_client,auth_service,session_store}.dart`,
`lib/state/{auth_repository,auth_scope}.dart` and
`lib/screens/{auth_gate,login_screen,register_screen}.dart`.

## Reports, photos and deletion

`ReportRepository` (`lib/state/report_repository.dart`) is the single entry point
the screens use. It holds an in-memory list of the server's reports.

| Method | What it does |
| --- | --- |
| `load()` | `GET /api/reports` with the bearer token, newest first. On failure the previous (server-sourced) list is kept and `lastError` is set; signed-out callers end empty with no error |
| `submitReport(...)` | `POST /api/reports`, then caches the photo locally and uploads it with `POST /api/reports/:id/photo` |
| `deleteReport(id)` | `DELETE /api/reports/:id`, then removes it locally and cleans up the cached photo |
| `resolveReportImage(report)` | Returns the cached bytes, else fetches them from the authenticated `GET /api/reports/:id/photo` endpoint |

Details worth knowing:

- **Nothing is shown before the server accepts it.** `submitReport` only inserts
  the report after `POST /api/reports` returns 2xx, so a failed submission is
  never shown as saved. `ApiException` is rethrown so the UI can explain it.
- **A photo upload failure does not discard the report.** The report already
  exists on the server; the upload failure simply leaves `serverPhotoPath` null
  so the UI can be honest about the missing evidence.
- **Delete is server-first.** The local list is only updated after the server
  confirms, so a failed request never leaves the UI claiming a still-existing
  report is gone.
- **Field mapping.** The single location name the form collects is sent as both
  `area` and `address`. Ownership and geography (`userId`, `state`, `district`,
  role, password) are never sent: the backend derives them from the token.
- **Categories.** `Pothole / Road Damage` → `ROADS`, `Broken Streetlight` →
  `STREETLIGHTS`, `Water Supply` → `WATER`, `Garbage / Waste` → `WASTE`,
  `Drainage` → `DRAINAGE`, `Other` → `SAFETY`.

### Photo storage

The backend is the durable home of report photos. The device keeps only a
short-lived cache of the bytes the citizen attached, written to
`<app documents>/civiclens/report_images/<report-id>.<ext>` and referenced by
file name only, so the image renders instantly even offline. Image bytes never
end up in a preferences entry. The optional **profile picture** follows the same
shape under `profile_images/`, and its tiny reference lives in `profile.json`;
it stays on the device and is never uploaded.

Report and image transport lives in `lib/services/report_api_service.dart` and
`lib/services/api_client.dart`; local image caching lives in
`lib/services/report_store.dart`.

## Outbound network usage

- `POST /api/auth/register`, `POST /api/auth/login`, and — for a signed-in
  citizen — `GET/POST/DELETE /api/reports` and `POST/GET /api/reports/:id/photo`
  against the CIVICLENS backend. Base URL resolution lives in
  `lib/config/api_config.dart`.
- OpenStreetMap raster tiles (`tile.openstreetmap.org`) in the location picker.
- OpenStreetMap Nominatim `/search` and `/reverse` for place labels.

## Project structure

```
lib/
├── main.dart                    # app entry, home screen, navigation
├── config/api_config.dart       # backend base URL (--dart-define overridable)
├── models/
│   ├── civic_report.dart        # CivicReport, ReportStatus, ReportOrigin, StatusEvent
│   ├── auth_user.dart           # signed-in citizen profile
│   └── auth_session.dart        # token + user
├── services/
│   ├── report_api_service.dart  # backend create/fetch/photo/delete + mapping
│   ├── api_client.dart          # JSON + byte HTTP, error mapping, 401 hook
│   ├── report_store.dart        # local photo cache
│   ├── profile_store.dart       # optional device-local profile picture
│   ├── auth_service.dart        # register / login
│   ├── session_store.dart       # secure token persistence
│   ├── location_service.dart    # device location
│   └── place_search_service.dart# Nominatim search / reverse geocoding
├── state/                       # report repository + ReportScope, auth repository/scope
├── data/indian_states.dart      # bundled state list for registration
├── screens/                     # auth gate, login, register, report issue, my reports, details, profile, location picker
├── widgets/                     # status chip, timeline, list card, thumbnails, auth form controls
└── utils/report_format.dart     # category icons, location/date formatting
```

## Known limitations

- `dart:io` storage does not run on the web target, so the web build is
  unsupported; Android, iOS, macOS, Windows and Linux are supported.
- Reports live on the backend, so signing in on another device shows the same
  reports; the device-local photo cache and optional profile picture do not
  follow the citizen to another device.
- The backend is reached over plain HTTP while developing; release builds keep
  Android's cleartext block and require HTTPS.
- There is no `/api/auth/me`, so a saved session is validated locally (expiry)
  and authoritatively per protected request; it is not re-verified at launch.
- Android's launch screen cannot be held open past Flutter's first frame, so the
  session is restored before that frame; `LaunchPlaceholder` is only a
  non-blank, launch-styled fallback for a status that stays unresolved.
- Widget tests use in-memory doubles, because `dart:io` operations started
  inside the Flutter test binding's `FakeAsync` zone never complete. Real disk
  behaviour is covered by the store unit tests.

Further design notes: [docs/TECHNICAL_DESIGN.md](docs/TECHNICAL_DESIGN.md).
