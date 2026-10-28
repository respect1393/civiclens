import { randomBytes } from "crypto";
import express from "express";
import cors from "cors";
import helmet from "helmet";
import { prisma } from "./db";
import { z } from "zod";
import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import { getJwtSecret, getUploadDir, MAX_IMAGE_BYTES } from "./config";
import {
  detectImageFormat,
  deleteImageIfExists,
  ensureDir,
  imageExists,
  mimeTypeForKey,
  reportImageKey,
  resolveWithin,
  writeImageAtomic,
} from "./storage";

// Extend Express Request type to include user
declare global {
  namespace Express {
    interface Request {
      user?: {
        id: string;
        email: string;
        role: string;
        state?: string | null;
        district?: string | null;
      };
    }
  }
}

/** Fixed-window parameters for the login rate limiter. */
const LOGIN_RATE_LIMIT_WINDOW_MS = 15 * 60 * 1000; // 15 minutes
const LOGIN_RATE_LIMIT_MAX = 10; // requests per client IP per window

export interface LoginRateLimitOptions {
  windowMs?: number;
  max?: number;
  /** Injectable clock so the window can be advanced deterministically in tests. */
  now?: () => number;
}

export interface CreateAppOptions {
  loginRateLimit?: LoginRateLimitOptions;
  /** Override the image upload root (used by tests for a disposable directory). */
  uploadDir?: string;
}

/**
 * Wraps `express.raw` so an oversized or unreadable body becomes a clear JSON
 * response instead of reaching the generic 500 handler. Only this route is
 * affected; the rest of the app keeps its existing error behaviour.
 */
function rawImageBodyParser() {
  const parser = express.raw({ type: () => true, limit: MAX_IMAGE_BYTES });
  return (
    req: express.Request,
    res: express.Response,
    next: express.NextFunction
  ) => {
    parser(req, res, (error: unknown) => {
      if (!error) return next();
      const status = (error as { status?: number; statusCode?: number }).status;
      const code = (error as { statusCode?: number }).statusCode;
      if (status === 413 || code === 413) {
        res.status(413).json({
          error: `The image is too large. The maximum size is ${Math.floor(
            MAX_IMAGE_BYTES / (1024 * 1024)
          )} MB.`,
        });
        return;
      }
      res.status(400).json({
        error: "The image could not be read. Please upload a JPEG, PNG or WebP file.",
      });
    });
  };
}

/**
 * In-memory, per-IP fixed-window limiter for POST /api/auth/login.
 *
 * The key is `req.ip`, which (with Express's default `trust proxy = false`)
 * is the socket address and ignores client-supplied X-Forwarded-For. It never
 * locks an account: only the offending IP is throttled, and it recovers
 * automatically once the window rolls over.
 */
function createLoginRateLimiter(options: LoginRateLimitOptions = {}) {
  const windowMs = options.windowMs ?? LOGIN_RATE_LIMIT_WINDOW_MS;
  const max = options.max ?? LOGIN_RATE_LIMIT_MAX;
  const now = options.now ?? (() => Date.now());

  const attempts = new Map<string, number[]>();

  return (
    req: express.Request,
    res: express.Response,
    next: express.NextFunction
  ) => {
    const clientIp = req.ip ?? req.socket.remoteAddress ?? "unknown";
    const currentTime = now();
    const windowStart = currentTime - windowMs;

    const recent = (attempts.get(clientIp) ?? []).filter(
      (timestamp) => timestamp > windowStart
    );

    if (recent.length >= max) {
      res.status(429).json({
        error: "Too many login attempts. Please try again later.",
      });
      return;
    }

    recent.push(currentTime);
    attempts.set(clientIp, recent);
    next();
  };
}

export function createApp(options: CreateAppOptions = {}) {
  const JWT_SECRET = getJwtSecret();

  const app = express();

  // Absolute root for report images. Created eagerly so a fresh clone does not
  // need a checked-in directory; writes re-create it defensively.
  const uploadDir = options.uploadDir ?? getUploadDir();
  void ensureDir(uploadDir).catch((error) => {
    console.error("Could not create the upload directory:", error);
  });

  const loginRateLimiter = createLoginRateLimiter(options.loginRateLimit);

  // Middleware
  app.use(helmet());
  app.use(cors());
  app.use(express.json({ limit: "1mb" }));

  // Zod schemas
  const registerSchema = z.object({
    name: z.string().min(1, "Name is required"),
    email: z.string().email("Invalid email address"),
    password: z.string().min(8, "Password must be at least 8 characters long"),
    state: z.string().min(1, "State is required"),
    district: z.string().min(1, "District is required"),
  });

  const loginSchema = z.object({
    email: z.string().email("Invalid email address"),
    password: z.string().min(1, "Password is required"),
  });

  const reportCreateSchema = z.object({
    title: z.string().min(1, "Title is required"),
    description: z.string().min(1, "Description is required"),
    category: z.enum(["ROADS", "STREETLIGHTS", "WATER", "WASTE", "DRAINAGE", "SAFETY"]),
    area: z.string().min(1, "Area is required"),
    address: z.string().min(1, "Address is required"),
    landmark: z.string().optional(),
    latitude: z.number().min(-90).max(90).optional(),
    longitude: z.number().min(-180).max(180).optional(),
  });

  const reportStatusUpdateSchema = z.object({
    status: z.enum([
      "SUBMITTED",
      "UNDER_REVIEW",
      "IN_PROGRESS",
      "RESOLVED",
      "REJECTED",
    ]),
  });

  const adminNoteCreateSchema = z.object({
    content: z
      .string()
      .trim()
      .min(1, "Note content is required")
      .max(2000, "Note content must be 2000 characters or fewer"),
  });

  // Authentication middleware
  const authenticate = async (
    req: express.Request,
    res: express.Response,
    next: express.NextFunction
  ) => {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith("Bearer ")) {
      return res.status(401).json({ error: "Unauthorized" });
    }

    const token = authHeader.substring(7);
    try {
      const payload = jwt.verify(token, JWT_SECRET, {
        algorithms: ["HS256"],
      }) as {
        id: string;
        email: string;
        role: string;
      };
      // Fetch fresh user data from DB to ensure we have latest state/district and role
      const user = await prisma.user.findUnique({
        where: { id: payload.id },
        select: {
          id: true,
          email: true,
          role: true,
          state: true,
          district: true,
        },
      });

      if (!user) {
        return res.status(401).json({ error: "Unauthorized" });
      }

      req.user = user;
      next();
    } catch (error) {
      return res.status(401).json({ error: "Unauthorized" });
    }
  };

  /**
   * Authorization middleware for administrator-only routes. Registered after
   * `authenticate`, so `req.user` is always populated from the database (the
   * DB role is authoritative, not the role embedded in the token).
   */
  const requireAdmin = (
    req: express.Request,
    res: express.Response,
    next: express.NextFunction
  ) => {
    if (req.user?.role !== "ADMIN") {
      return res
        .status(403)
        .json({ error: "Forbidden: insufficient permissions" });
    }
    next();
  };

  /**
   * Whether [user] may read reports owned by [ownerId] in [state]/[district].
   *
   * Mirrors the GET /api/reports/:id rule exactly: administrators see every
   * report, citizens only those matching their own state (and district when
   * they have one).
   */
  const canViewReport = (
    user: { id: string; role: string; state: string | null; district: string | null },
    report: { state: string | null; district: string | null }
  ): boolean => {
    if (user.role === "ADMIN") return true;
    if (!user.state || !report.state || report.state !== user.state) return false;
    if (user.district && report.district !== user.district) return false;
    return true;
  };

  /**
   * Prisma `include` shared by every report read. `statusHistory` and
   * `adminNotes` are internal to administrators: citizens never receive them,
   * so the mobile client's response shape stays byte-for-byte unchanged and
   * private notes cannot leak across districts.
   */
  const reportInclude = (role: string) => ({
    user: {
      select: {
        id: true,
        name: true,
        email: true,
      },
    },
    ...(role === "ADMIN"
      ? {
          statusHistory: { orderBy: { changedAt: "asc" as const } },
          adminNotes: {
            orderBy: { createdAt: "desc" as const },
            include: {
              admin: { select: { id: true, name: true, email: true } },
            },
          },
        }
      : {}),
  });

  /**
   * Removes a stored image once no report still references it.
   *
   * Called *after* the database already points away from (or no longer
   * contains) the reference, so a failure here leaves at worst an unreferenced
   * file behind — it can never break a live report. Returns whether the file
   * was actually removed.
   */
  const removeImageIfOrphaned = async (
    key: string | null,
    excludeReportId: string
  ): Promise<boolean> => {
    if (!key) return false;

    const stillReferenced = await prisma.report.count({
      where: { photoPath: key, id: { not: excludeReportId } },
    });
    if (stillReferenced > 0) return false;

    const absolute = resolveWithin(uploadDir, key);
    if (!absolute) return false;

    try {
      await deleteImageIfExists(absolute);
      return true;
    } catch (error) {
      console.error("Could not delete an orphaned report image:", error);
      return false;
    }
  };

  // Health endpoint
  app.get("/api/health", (_req, res) => {
    res.json({
      status: "ok",
      service: "civiclens-backend",
    });
  });

  // Auth endpoints
  app.post("/api/auth/register", async (req, res) => {
    try {
      // Validate input
      const result = registerSchema.safeParse(req.body);
      if (!result.success) {
        return res.status(400).json({
          error: "Invalid registration data",
          details: result.error.format(),
        });
      }

      const { name, email, password, state, district } = result.data;

      // Check if email already exists
      const existingUser = await prisma.user.findUnique({
        where: { email },
      });

      if (existingUser) {
        return res.status(400).json({
          error: "Email already registered",
        });
      }

      // Hash password
      const hashedPassword = await bcrypt.hash(password, 10);

      // Create user (role is always CITIZEN for public registration)
      const user = await prisma.user.create({
        data: {
          name,
          email,
          passwordHash: hashedPassword,
          role: "CITIZEN",
          state,
          district,
        },
        select: {
          id: true,
          name: true,
          email: true,
          state: true,
          district: true,
          role: true,
        },
      });

      // Generate JWT
      const token = jwt.sign(
        { id: user.id, email: user.email, role: user.role },
        JWT_SECRET,
        { expiresIn: "7d", algorithm: "HS256" }
      );

      res.status(201).json({
        user,
        token,
      });
    } catch (error) {
      console.error("Registration error:", error);
      res.status(500).json({ error: "Internal server error" });
    }
  });

  app.post("/api/auth/login", loginRateLimiter, async (req, res) => {
    try {
      // Validate input
      const result = loginSchema.safeParse(req.body);
      if (!result.success) {
        return res.status(400).json({
          error: "Invalid login data",
          details: result.error.format(),
        });
      }

      const { email, password } = result.data;

      // Find user by email
      const user = await prisma.user.findUnique({
        where: { email },
      });

      if (!user) {
        // Generic error to prevent user enumeration
        return res.status(401).json({ error: "Invalid credentials" });
      }

      // Verify password
      const passwordValid = await bcrypt.compare(password, user.passwordHash);
      if (!passwordValid) {
        return res.status(401).json({ error: "Invalid credentials" });
      }

      // Generate JWT
      const token = jwt.sign(
        { id: user.id, email: user.email, role: user.role },
        JWT_SECRET,
        { expiresIn: "7d", algorithm: "HS256" }
      );

      // Return safe user object
      const safeUser = {
        id: user.id,
        name: user.name,
        email: user.email,
        state: user.state,
        district: user.district,
        role: user.role,
      };

      res.json({
        user: safeUser,
        token,
      });
    } catch (error) {
      console.error("Login error:", error);
      res.status(500).json({ error: "Internal server error" });
    }
  });

  // Report endpoints (protected)
  app.post("/api/reports", authenticate, async (req, res) => {
    try {
      // Validate input
      const result = reportCreateSchema.safeParse(req.body);
      if (!result.success) {
        return res.status(400).json({
          error: "Invalid report data",
          details: result.error.format(),
        });
      }

      const {
        title,
        description,
        category,
        area,
        address,
        landmark,
        latitude,
        longitude,
      } = result.data;

      // Get authenticated user
      const user = req.user as {
        id: string;
        role: string;
        state: string | null;
        district: string | null;
      };

      // Ensure user has state and district (should be enforced at registration, but double-check)
      if (!user.state || !user.district) {
        return res.status(400).json({
          error: "User profile incomplete: state and district required",
        });
      }

      // Create report with authenticated user's ID and geographic info
      const report = await prisma.report.create({
        data: {
          title,
          description,
          category,
          area,
          address,
          landmark,
          latitude,
          longitude,
          userId: user.id,
          state: user.state,
          district: user.district,
        },
        include: reportInclude(user.role),
      });

      res.status(201).json(report);
    } catch (error) {
      console.error("Error creating report:", error);
      res.status(500).json({ error: "Internal server error" });
    }
  });

  // GET /api/reports - Retrieve reports with pagination and geographic filtering.
//
// Access rules depend on the `mine` query parameter:
//   - mine=true:  ownership view — only reports submitted by the authenticated
//                 account (citizen or administrator).
//   - mine unset: scope view — citizens see their state/district; administrators
//                 see only their registered state across all districts.
//
// A `district` query parameter lets a citizen explore another district within
// their own state. The state filter is always the citizen's registered state,
// so a district from another state can never leak through.
  app.get("/api/reports", authenticate, async (req, res) => {
    try {
      const user = req.user as {
        id: string;
        role: string;
        state: string | null;
        district: string | null;
      };

      // Safely parse pagination parameters
      const parsePage = (page: any) => {
        const num = Array.isArray(page) ? parseInt(page[0]) : parseInt(page);
        return isNaN(num) ? 1 : Math.max(num, 1);
      };
      const parseLimit = (limit: any) => {
        const num = Array.isArray(limit) ? parseInt(limit[0]) : parseInt(limit);
        return isNaN(num) ? 20 : Math.min(Math.max(num, 1), 100);
      };

      const page = parsePage(req.query.page);
      const limit = parseLimit(req.query.limit);
      const skip = (page - 1) * limit;

      // `mine=true` requests an ownership view: only this account's reports.
      const mine = req.query.mine === "true" || req.query.mine === "1";

      // `district` lets a citizen explore another district within their state.
      const districtParam =
        typeof req.query.district === "string" ? req.query.district : undefined;

      // Build where clause based on user role and view mode.
      let whereClause: any = {};

      if (mine) {
        // Ownership view: only reports submitted by the authenticated account.
        whereClause = { userId: user.id };
      } else if (user.role === "CITIZEN") {
        // Citizens can only see reports from their own state.
        if (!user.state) {
          // A citizen without a state must see no reports at all.
          whereClause = {
            id: { in: [] },
          };
        } else {
          whereClause = { state: user.state };
          // District: explicit exploration parameter overrides the registered
          // district; otherwise fall back to the registered district.
          const district = districtParam ?? user.district;
          if (district) {
            whereClause.district = district;
          }
        }
      } else {
        // Administrators see only reports from their registered state.
        if (!user.state) {
          whereClause = {
            id: { in: [] },
          };
        } else {
          whereClause = { state: user.state };
        }
      }

      // Get total count for pagination metadata
      const total = await prisma.report.count({ where: whereClause });

      // Get reports with associated citizen info, sorted newest first
      const reports = await prisma.report.findMany({
        where: whereClause,
        skip,
        take: limit,
        orderBy: {
          createdAt: "desc",
        },
        include: reportInclude(user.role),
      });

      // Return consistent JSON response with reports and pagination metadata
      res.json({
        data: reports,
        pagination: {
          page,
          limit,
          total,
          totalPages: Math.ceil(total / limit),
        },
      });
    } catch (error) {
      console.error("Error fetching reports:", error);
      res.status(500).json({ error: "Internal server error" });
    }
  });

  // GET /api/reports/:id - Retrieve one report by ID with authorization check
  app.get("/api/reports/:id", authenticate, async (req, res) => {
    try {
      const { id } = req.params;
      const user = req.user as {
        id: string;
        role: string;
        state: string | null;
        district: string | null;
      };

      const idParam = req.params.id;
      const reportId = Array.isArray(idParam) ? idParam[0] : idParam;

      const report = await prisma.report.findUnique({
        where: { id: reportId },
        include: reportInclude(user.role),
      });

      if (!report) {
        return res.status(404).json({
          error: "Report not found",
        });
      }

      // Authorization check
      if (user.role === "CITIZEN") {
        // Citizens can only access reports from their state
        if (!report.state || !user.state || report.state !== user.state) {
          return res.status(403).json({
            error: "Forbidden: insufficient permissions",
          });
        }
        // If citizen has a district, report must match district too
        if (user.district && report.district !== user.district) {
          return res.status(403).json({
            error: "Forbidden: insufficient permissions",
          });
        }
      } else {
        // Administrators can only access reports from their registered state.
        if (!user.state || !report.state || report.state !== user.state) {
          return res.status(403).json({
            error: "Forbidden: insufficient permissions",
          });
        }
      }

      res.json(report);
    } catch (error) {
      console.error("Error fetching report:", error);
      res.status(500).json({ error: "Internal server error" });
    }
  });

  // PATCH /api/reports/:id/status - administrator-only status transition.
  //
  // The report's status and its StatusHistory record are written in a single
  // transaction, so the log can never disagree with the current status. The
  // acting administrator is deliberately not stored here: the StatusHistory
  // model has no actor column, and inventing one would misrepresent the data.
  app.patch(
    "/api/reports/:id/status",
    authenticate,
    requireAdmin,
    async (req, res) => {
      try {
        const result = reportStatusUpdateSchema.safeParse(req.body);
        if (!result.success) {
          return res.status(400).json({
            error: "Invalid status update data",
            details: result.error.format(),
          });
        }

        const idParam = req.params.id;
        const reportId = Array.isArray(idParam) ? idParam[0] : idParam;

const existing = await prisma.report.findUnique({
        where: { id: reportId },
        select: { id: true, status: true, state: true },
      });

      if (!existing) {
        return res.status(404).json({ error: "Report not found" });
      }

      // Administrators can only modify reports in their registered state.
      const user = req.user as {
        id: string;
        role: string;
        state: string | null;
        district: string | null;
      };
      if (user.role === "ADMIN") {
        if (!user.state || !existing.state || existing.state !== user.state) {
          return res.status(403).json({
            error: "Forbidden: insufficient permissions",
          });
        }
      }

      const { status } = result.data;

        // Re-asserting the current status is a no-op: return the report without
        // appending a duplicate, misleading history entry.
        if (existing.status === status) {
          const current = await prisma.report.findUnique({
            where: { id: reportId },
            include: reportInclude("ADMIN"),
          });
          return res.json(current);
        }

        const [, updated] = await prisma.$transaction([
          prisma.statusHistory.create({
            data: {
              reportId,
              oldStatus: existing.status,
              newStatus: status,
            },
          }),
          prisma.report.update({
            where: { id: reportId },
            data: { status },
            include: reportInclude("ADMIN"),
          }),
        ]);

        res.json(updated);
      } catch (error) {
        console.error("Error updating report status:", error);
        res.status(500).json({ error: "Internal server error" });
      }
    }
  );

  // POST /api/reports/:id/notes - administrator-only administrative note.
  //
  // The note is attributed to the authenticated administrator's id (from the
  // database-backed session, never the request body).
  app.post(
    "/api/reports/:id/notes",
    authenticate,
    requireAdmin,
    async (req, res) => {
      try {
        const result = adminNoteCreateSchema.safeParse(req.body);
        if (!result.success) {
          return res.status(400).json({
            error: "Invalid note data",
            details: result.error.format(),
          });
        }

        const idParam = req.params.id;
        const reportId = Array.isArray(idParam) ? idParam[0] : idParam;
        const user = req.user as { id: string; state: string | null };

        const report = await prisma.report.findUnique({
          where: { id: reportId },
          select: { id: true, state: true },
        });

        if (!report) {
          return res.status(404).json({ error: "Report not found" });
        }

        // Administrators can only add notes to reports in their registered state.
        if (!user.state || !report.state || report.state !== user.state) {
          return res.status(403).json({
            error: "Forbidden: insufficient permissions",
          });
        }

        const note = await prisma.adminNote.create({
          data: {
            reportId,
            adminId: user.id,
            content: result.data.content,
          },
          include: {
            admin: { select: { id: true, name: true, email: true } },
          },
        });

        res.status(201).json(note);
      } catch (error) {
        console.error("Error creating administrative note:", error);
        res.status(500).json({ error: "Internal server error" });
      }
    }
  );

  // POST /api/reports/:id/photo - store the report's image on the backend.
  //
  // The raw request body is the image itself (no multipart, no base64) so the
  // bytes are validated directly and written under a server-controlled,
  // content-addressed name. Only the report's owner may attach a photo.
  app.post(
    "/api/reports/:id/photo",
    authenticate,
    rawImageBodyParser(),
    async (req, res) => {
      try {
        const idParam = req.params.id;
        const reportId = Array.isArray(idParam) ? idParam[0] : idParam;
        const user = req.user as { id: string; role: string };

        const report = await prisma.report.findUnique({
          where: { id: reportId },
          select: { id: true, userId: true, photoPath: true },
        });

        if (!report) {
          return res.status(404).json({ error: "Report not found" });
        }

        // Ownership: only the citizen who filed the report may attach evidence.
        if (report.userId !== user.id) {
          return res.status(403).json({
            error: "Forbidden: insufficient permissions",
          });
        }

        const buffer = Buffer.isBuffer(req.body) ? req.body : null;
        if (!buffer || buffer.length === 0) {
          return res.status(400).json({
            error: "An image file is required in the request body.",
          });
        }

        const format = detectImageFormat(buffer);
        if (!format) {
          return res.status(400).json({
            error:
              "Unsupported image format. Please upload a JPEG, PNG or WebP image.",
          });
        }

        const key = reportImageKey(buffer, format);
        const absolute = resolveWithin(uploadDir, key);
        if (!absolute) {
          // Cannot happen for a generated key, but never write outside the root.
          return res.status(500).json({ error: "Internal server error" });
        }

        const previous = report.photoPath;

        try {
          await writeImageAtomic(absolute, buffer);
        } catch (error) {
          console.error("Error storing report image:", error);
          return res.status(500).json({ error: "Internal server error" });
        }

        try {
          await prisma.report.update({
            where: { id: reportId },
            data: { photoPath: key },
          });
        } catch (error) {
          // The database still points at the old value (or nothing): drop the
          // newly written file unless another report already uses it.
          await removeImageIfOrphaned(key, reportId);
          console.error("Error attaching report image:", error);
          return res.status(500).json({ error: "Internal server error" });
        }

        // The switch succeeded; the old image is now unreferenced by this
        // report and is removed only if no other report points at it.
        if (previous && previous !== key) {
          await removeImageIfOrphaned(previous, reportId);
        }

        res.json({ id: reportId, photoPath: key });
      } catch (error) {
        console.error("Error uploading report image:", error);
        res.status(500).json({ error: "Internal server error" });
      }
    }
  );

  // GET /api/reports/:id/photo - authenticated image retrieval.
  //
  // Images are never served as uncontrolled static files: every request is
  // authenticated and re-checked against the same visibility rule as the
  // report itself, so a citizen cannot read another area's private photos.
  app.get("/api/reports/:id/photo", authenticate, async (req, res) => {
    try {
      const idParam = req.params.id;
      const reportId = Array.isArray(idParam) ? idParam[0] : idParam;
      const user = req.user as {
        id: string;
        role: string;
        state: string | null;
        district: string | null;
      };

      const report = await prisma.report.findUnique({
        where: { id: reportId },
        select: { id: true, photoPath: true, state: true, district: true },
      });

      if (!report) {
        return res.status(404).json({ error: "Report not found" });
      }

      if (!canViewReport(user, report)) {
        return res.status(403).json({
          error: "Forbidden: insufficient permissions",
        });
      }

      if (!report.photoPath) {
        return res.status(404).json({ error: "No image for this report" });
      }

      const absolute = resolveWithin(uploadDir, report.photoPath);
      if (!absolute || !(await imageExists(absolute))) {
        return res.status(404).json({ error: "No image for this report" });
      }

      res.setHeader(
        "Content-Type",
        mimeTypeForKey(report.photoPath) ?? "application/octet-stream"
      );
      // Private citizen images: shared caches must not retain them.
      res.setHeader("Cache-Control", "private, max-age=300");
      res.sendFile(absolute, (error) => {
        if (error && !res.headersSent) {
          res.status(404).json({ error: "No image for this report" });
        }
      });
    } catch (error) {
      console.error("Error serving report image:", error);
      if (!res.headersSent) {
        res.status(500).json({ error: "Internal server error" });
      }
    }
  });

  // DELETE /api/reports/:id - authenticated, owner-only report deletion.
  app.delete("/api/reports/:id", authenticate, async (req, res) => {
    try {
      const idParam = req.params.id;
      const reportId = Array.isArray(idParam) ? idParam[0] : idParam;
      const user = req.user as { id: string; role: string };

      const report = await prisma.report.findUnique({
        where: { id: reportId },
        select: { id: true, userId: true, photoPath: true },
      });

      if (!report) {
        return res.status(404).json({ error: "Report not found" });
      }

      // Ownership is stricter than viewing: a citizen may see reports in their
      // area but may only ever delete the ones they filed themselves.
      if (report.userId !== user.id) {
        return res.status(403).json({
          error: "Forbidden: insufficient permissions",
        });
      }

      // Remove the database record first. Related status history and admin
      // notes cascade. Only then is the image considered for cleanup.
      await prisma.report.delete({ where: { id: reportId } });

      const imageDeleted = report.photoPath
        ? await removeImageIfOrphaned(report.photoPath, reportId)
        : false;

      res.json({ id: reportId, deleted: true, imageDeleted });
    } catch (error) {
      console.error("Error deleting report:", error);
      res.status(500).json({ error: "Internal server error" });
    }
  });

  // Admin-only account management endpoints.
  //
  // GET /api/admins and POST /api/admins require a live, database-backed
  // session whose role is ADMIN. The role is always assigned server-side:
  // the client can never promote a citizen, and a request body that carries
  // a `role` field is ignored.

  // POST /api/invitations lets an authenticated administrator issue a
  // single-use invitation token for creating a new administrator account.
  // The invitation is tied to a specific email and expires after 7 days.

  /** Shape returned for every administrator row. No password hash or token. */
  const safeAdmin = (user: {
    id: string;
    name: string;
    email: string;
    role: string;
    state: string | null;
    district: string | null;
    createdAt: Date;
  }) => ({
    id: user.id,
    name: user.name,
    email: user.email,
    role: user.role,
    state: user.state,
    district: user.district,
    createdAt: user.createdAt.toISOString(),
  });

  const adminCreateSchema = z.object({
    name: z.string().trim().min(1, "Name is required"),
    email: z.string().email("Invalid email address"),
    password: z.string().min(8, "Password must be at least 8 characters long"),
    state: z.string().trim().min(1, "State is required"),
    district: z.string().trim().optional(),
  });

  const invitationCreateSchema = z.object({
    email: z.string().email("Invalid email address"),
  });

  // GET /api/admins - list every administrator account.
  app.get("/api/admins", authenticate, requireAdmin, async (_req, res) => {
    try {
      const admins = await prisma.user.findMany({
        where: { role: "ADMIN" },
        orderBy: { createdAt: "desc" },
        select: {
          id: true,
          name: true,
          email: true,
          role: true,
          state: true,
          district: true,
          createdAt: true,
        },
      });

      res.json({ data: admins.map(safeAdmin) });
    } catch (error) {
      console.error("Error listing administrators:", error);
      res.status(500).json({ error: "Internal server error" });
    }
  });

  // POST /api/admins - create a new administrator account.
  //
  // This endpoint remains administrator-only. It is not used by the public
  // login page: public administrator creation goes through
  // POST /api/auth/register-admin with a valid single-use invitation.
  app.post("/api/admins", authenticate, requireAdmin, async (req, res) => {
    try {
      const result = adminCreateSchema.safeParse(req.body);
      if (!result.success) {
        return res.status(400).json({
          error: "Invalid administrator data",
          details: result.error.format(),
        });
      }

      // Normalize email consistently (trim + lowercase) before any lookup or
      // storage so "Foo@Example.com" and "foo@example.com" collide.
      const email = result.data.email.trim().toLowerCase();
      const name = result.data.name.trim();
      const state = result.data.state.trim();
      const district = result.data.district?.trim() || null;

      const existingUser = await prisma.user.findUnique({
        where: { email },
      });

      if (existingUser) {
        return res.status(409).json({ error: "Email already registered" });
      }

      // bcrypt work factor matches the established registration flow (cost 10).
      const hashedPassword = await bcrypt.hash(result.data.password, 10);

      // The role is always ADMIN here. Any client-supplied `role` in the body
      // is ignored because the schema above does not include a role field.
      const user = await prisma.user.create({
        data: {
          name,
          email,
          passwordHash: hashedPassword,
          role: "ADMIN",
          state,
          district,
        },
        select: {
          id: true,
          name: true,
          email: true,
          role: true,
          state: true,
          district: true,
          createdAt: true,
        },
      });

      res.status(201).json(safeAdmin(user));
    } catch (error) {
      // Prisma unique constraint violations (P2002) are mapped to a clean 409
      // instead of leaking the driver error to the caller.
      if (
        error instanceof Error &&
        "code" in error &&
        (error as { code?: string }).code === "P2002"
      ) {
        return res.status(409).json({ error: "Email already registered" });
      }

      console.error("Error creating administrator:", error);
      res.status(500).json({ error: "Internal server error" });
    }
  });

  // POST /api/invitations - issue a single-use administrator invitation.
  //
  // Only an authenticated administrator may create invitations. The invitation
  // is bound to a specific email address and expires after 7 days.
  app.post("/api/invitations", authenticate, requireAdmin, async (req, res) => {
    try {
      const result = invitationCreateSchema.safeParse(req.body);
      if (!result.success) {
        return res.status(400).json({
          error: "Invalid invitation data",
          details: result.error.format(),
        });
      }

      const email = result.data.email.trim().toLowerCase();

      // A single-use invitation cannot coexist with an unused one for the same
      // email. Revoke any unused invitation for this email first.
      await prisma.invitation.updateMany({
        where: { email, usedAt: null },
        data: { usedAt: new Date() },
      });

      const token = randomBytes(32).toString("hex");
      const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

      const invitation = await prisma.invitation.create({
        data: {
          token,
          email,
          createdById: req.user!.id,
          expiresAt,
        },
        select: {
          id: true,
          token: true,
          email: true,
          expiresAt: true,
        },
      });

      res.status(201).json(invitation);
    } catch (error) {
      console.error("Error creating invitation:", error);
      res.status(500).json({ error: "Internal server error" });
    }
  });

  // POST /api/auth/register-admin - create an administrator account using a
  // valid single-use invitation. Publicly accessible but gated by the
  // invitation, so no unprotected administrator registration is possible.
  app.post("/api/auth/register-admin", async (req, res) => {
    try {
      const schema = z.object({
        invitationToken: z.string().min(1, "Invitation code is required"),
        name: z.string().trim().min(1, "Name is required"),
        email: z.string().email("Invalid email address"),
        password: z.string().min(8, "Password must be at least 8 characters long"),
        confirmPassword: z.string().min(1, "Please confirm your password"),
        state: z.string().trim().min(1, "State is required"),
        district: z.string().trim().optional(),
      });

      const result = schema.safeParse(req.body);
      if (!result.success) {
        return res.status(400).json({
          error: "Invalid registration data",
          details: result.error.format(),
        });
      }

      const {
        invitationToken,
        name,
        email,
        password,
        confirmPassword,
        state,
        district,
      } = result.data;

      if (password !== confirmPassword) {
        return res.status(400).json({
          error: "Passwords do not match",
        });
      }

      // Look up the invitation.
      const invitation = await prisma.invitation.findUnique({
        where: { token: invitationToken },
        include: { createdBy: true },
      });

      if (!invitation) {
        return res.status(400).json({
          error: "Invalid invitation code",
        });
      }

      // Single-use: already consumed.
      if (invitation.usedAt !== null) {
        return res.status(400).json({
          error: "Invitation code has already been used",
        });
      }

      // Expired.
      if (invitation.expiresAt < new Date()) {
        return res.status(400).json({
          error: "Invitation code has expired",
        });
      }

      // The invitation is bound to a specific email.
      const normalizedEmail = email.trim().toLowerCase();
      if (invitation.email !== normalizedEmail) {
        return res.status(400).json({
          error: "Invitation code is not valid for this email address",
        });
      }

      // Email must not already exist.
      const existingUser = await prisma.user.findUnique({
        where: { email: normalizedEmail },
      });

      if (existingUser) {
        return res.status(409).json({ error: "Email already registered" });
      }

      // bcrypt work factor matches the established registration flow (cost 10).
      const hashedPassword = await bcrypt.hash(password, 10);

      // Create the administrator account and mark the invitation as used so it
  // cannot be reused. The user is created first, then the invitation is
  // marked as consumed with the new administrator's id.
      const user = await prisma.user.create({
        data: {
          name: name.trim(),
          email: normalizedEmail,
          passwordHash: hashedPassword,
          role: "ADMIN",
          state: state.trim(),
          district: district?.trim() || null,
        },
        select: {
          id: true,
          name: true,
          email: true,
          role: true,
          state: true,
          district: true,
          createdAt: true,
        },
      });

      await prisma.invitation.update({
        where: { id: invitation.id },
        data: { usedAt: new Date(), usedById: user.id },
      });

      res.status(201).json(safeAdmin(user));
    } catch (error) {
      // Prisma unique constraint violations (P2002) are mapped to a clean 409
      // instead of leaking the driver error to the caller.
      if (
        error instanceof Error &&
        "code" in error &&
        (error as { code?: string }).code === "P2002"
      ) {
        return res.status(409).json({ error: "Email already registered" });
      }

      console.error("Error creating administrator via invitation:", error);
      res.status(500).json({ error: "Internal server error" });
    }
  });

  // JSON 404 for any route that was not matched above. Must be registered after
  // every route so Express reaches it only when no handler responded.
  app.use((_req, res) => {
    res.status(404).json({ error: "Not found" });
  });

  // Centralized error handler. Express identifies an error handler by its
  // four-argument signature, so the (unused) `next` parameter is required.
  // Only a generic message is returned: no stack traces, database details or
  // internal error messages ever reach the client.
  app.use(
    (
      err: Error,
      _req: express.Request,
      res: express.Response,
      _next: express.NextFunction
    ) => {
      console.error("Unhandled error:", err);
      if (!res.headersSent) {
        res.status(500).json({ error: "Internal server error" });
      }
    }
  );

  return app;
}
