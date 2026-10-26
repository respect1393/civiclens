# CIVICLENS

**Your City. Your Voice. Visible Change.**
Theme: Urban Inclusion & Infrastructure · Team GenEvo

CIVICLENS is a civic-issue reporting system: citizens report local problems
(potholes, broken streetlights, water supply, waste, drainage), attach a photo,
and track the report's status, while a backend keeps the authoritative record
and an admin dashboard is intended to manage the pipeline.

> **Prototype notice.** This is a hackathon prototype. Submitting a report or
> creating an account sends real requests to the local backend, but there is no
> city department behind it: nothing is dispatched to a real authority. Plain
> HTTP is used for local development only and must never ship.

This repository contains three independent projects that share one backend:

| Project | Stack | Purpose |
| --- | --- | --- |
| `backend/` | Node.js · Express 5 · TypeScript · Prisma 7 · SQLite | REST API: authentication, reports, report photos |
| `mobile/` | Flutter · Dart | Citizen app (Android, iOS, desktop) |
| `admin/` | React · Vite · TypeScript | Admin dashboard (in progress) |

The **mobile** app is the most complete. See `mobile/README.md` for the detailed
app documentation and `mobile/docs/TECHNICAL_DESIGN.md` for its architecture.

---

## Prerequisites

| Tool | Version used | Notes |
| --- | --- | --- |
| Node.js | 20+ | For `backend/` and `admin/` |
| npm | Bundled with Node | Both projects ship a `package-lock.json` |
| Flutter | 3.47.1 (stable) | Includes Dart 3.13.1 |
| A device/emulator | Android, iOS, or desktop | Or use the Android emulator for the mobile app |

No paid services or cloud accounts are required: the backend uses a local SQLite
file and stores uploaded images on disk.

---

## 1. Backend

All commands run from `backend/`.

```bash
cd backend

# 1. Install dependencies.
npm install

# 2. Create your environment file from the documented example.
cp .env.example .env

# 3. Set a UNIQUE JWT secret in .env (the server refuses to start without one
#    of at least 32 characters). Never commit .env.
node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
#    Copy the printed value into JWT_SECRET="..." in backend/.env.

# 4. Generate the Prisma client (it is git-ignored and required to build).
npm run prisma:generate

# 5. Create/upgrade the SQLite database by applying the committed migrations.
#    This creates backend/dev.db and is safe to re-run.
npm run db:init

# 6. Start the API with hot reload on http://localhost:3000.
npm run dev
```

`backend/.env` keys (see `backend/.env.example` for the full explanation):

| Key | Default | Meaning |
| --- | --- | --- |
| `DATABASE_URL` | `file:./dev.db` | SQLite file, relative to `backend/` |
| `PORT` | `3000` | HTTP port the API listens on |
| `UPLOAD_DIR` | `./uploads` | Where report images are written |
| `JWT_SECRET` | — | Signing secret, **at least 32 characters**, unique per machine |

Useful backend scripts:

```bash
npm test              # run the API test suite (Vitest)
npm run db:migrate    # create a new migration while developing
npm run db:status     # show migration status
npm run db:studio     # open Prisma Studio against dev.db
npm run build         # compile TypeScript to dist/
npm start             # run the compiled server (after npm run build)
```

Runtime data that must never be committed is already ignored: `backend/dev.db`,
`backend/.env`, `backend/uploads/`, and the generated client in
`backend/src/generated/`.

---

## 2. Mobile app

All commands run from `mobile/`.

```bash
cd mobile
flutter pub get
flutter run                     # with a device or emulator attached
```

### Pointing the app at the backend

The base URL is resolved at runtime by `lib/config/api_config.dart`; nothing
hardcodes a host.

| Where the app runs | Base URL | Notes |
| --- | --- | --- |
| Android emulator | `http://10.0.2.2:3000` | default; `10.0.2.2` is the emulator's alias for the host loopback |
| Flutter on the same machine as the backend | `http://127.0.0.1:3000` | default on desktop |
| Physical phone / any other host | `http://<LAPTOP_LAN_IP>:3000` | pass it explicitly |

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.42:3000
```

The phone and the laptop must share a network and the laptop firewall must allow
port 3000. Plain HTTP is development-only: Android permits cleartext only in the
`debug`/`profile` manifests, and production must use HTTPS.

### Checks

```bash
cd mobile
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

---

## 3. Admin dashboard

All commands run from `admin/`. This project is a work in progress.

```bash
cd admin
npm install
npm run dev      # start the Vite dev server (prints its URL)
npm run build    # type-check and produce a production build in admin/dist
npm run preview  # preview the production build locally
```

---

## 🚀 Try the CIVICLENS Prototype

CIVICLENS is available as a temporarily hosted prototype for demonstration and testing.

| Component | Access |
|---|---|
| Admin Dashboard | [Open CIVICLENS Admin Dashboard](https://civiclens-mauve.vercel.app) |
| Backend API | Hosted API used by the mobile application and dashboard |
| Mobile Application | Install the provided Android application and connect to the hosted backend |

### How to Try CIVICLENS

1. Open the admin dashboard using the link above.
2. Install and launch the CIVICLENS mobile application on your Android device.
3. Register or sign in as a citizen.
4. Submit a civic issue with a photograph and location details.
5. View and manage submitted reports through the admin dashboard.

### For Admin Dashboard : 
1. Login Details are provided inside admin/auth.txt (Login detailed are provided here just for inspection).

> **Prototype Notice:** The hosted services are provided for demonstration and testing. CIVICLENS is not integrated with government or municipal authorities. Reports submitted through this prototype are not dispatched to real civic departments. Hosted services may be unavailable outside the demonstration period.
---

