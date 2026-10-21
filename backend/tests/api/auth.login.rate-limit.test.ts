import { describe, expect, it } from "vitest";
import request from "supertest";
import { createApp } from "../../src/app";
import { createUser } from "../helpers/factory";

const WINDOW_MS = 15 * 60 * 1000;
const MAX = 10;
const RATE_LIMIT_ERROR = "Too many login attempts. Please try again later.";

/** Builds an app whose login limiter uses a controllable virtual clock. */
function buildApp() {
  let clock = 0;
  const app = createApp({
    loginRateLimit: { windowMs: WINDOW_MS, max: MAX, now: () => clock },
  });
  return {
    app,
    advance: (ms: number) => {
      clock += ms;
    },
  };
}

function login(app: ReturnType<typeof buildApp>["app"], email: string, password: string) {
  return request(app).post("/api/auth/login").send({ email, password });
}

describe("POST /api/auth/login rate limiting", () => {
  it("allows 10 attempts then returns 429 for the 11th", async () => {
    const { app } = buildApp();
    const { user } = await createUser({ email: "limit@example.com" });

    for (let i = 0; i < MAX; i++) {
      const res = await login(app, user.email, "wrong-password");
      expect(res.status).toBe(401);
    }

    const blocked = await login(app, user.email, "wrong-password");
    expect(blocked.status).toBe(429);
    expect(blocked.headers["content-type"]).toContain("application/json");
    expect(blocked.body).toEqual({ error: RATE_LIMIT_ERROR });
  });

  it("counts successful logins toward the limit too", async () => {
    const { app } = buildApp();
    const { user, password } = await createUser({ email: "ok@example.com" });

    for (let i = 0; i < MAX; i++) {
      const res = await login(app, user.email, password);
      expect(res.status).toBe(200);
    }

    const blocked = await login(app, user.email, password);
    expect(blocked.status).toBe(429);
    expect(blocked.body).toEqual({ error: RATE_LIMIT_ERROR });
  });

  it("allows requests again once the 15-minute window expires", async () => {
    const { app, advance } = buildApp();
    const { user } = await createUser({ email: "window@example.com" });

    for (let i = 0; i < MAX; i++) {
      await login(app, user.email, "wrong-password");
    }
    expect((await login(app, user.email, "wrong-password")).status).toBe(429);

    // Still inside the window: remains blocked.
    advance(WINDOW_MS - 1);
    expect((await login(app, user.email, "wrong-password")).status).toBe(429);

    // Past the window: the counter resets and a fresh request is processed.
    advance(2);
    const afterWindow = await login(app, user.email, "wrong-password");
    expect(afterWindow.status).toBe(401);
  });

  it("does not rate-limit registration, health, or report endpoints", async () => {
    const { app } = buildApp();

    for (let i = 0; i < MAX + 5; i++) {
      expect((await request(app).get("/api/health")).status).toBe(200);
    }
    for (let i = 0; i < MAX + 5; i++) {
      // Invalid registration body still gets its normal 400, never 429.
      expect((await request(app).post("/api/auth/register").send({})).status).toBe(400);
    }
    for (let i = 0; i < MAX + 5; i++) {
      // Unauthenticated reports still get 401, never 429.
      expect((await request(app).get("/api/reports")).status).toBe(401);
    }
  });

  it("keeps limiter state isolated per app instance", async () => {
    const first = buildApp();
    const second = buildApp();
    const { user } = await createUser({ email: "isolated@example.com" });

    for (let i = 0; i < MAX; i++) {
      await login(first.app, user.email, "wrong-password");
    }
    expect((await login(first.app, user.email, "wrong-password")).status).toBe(429);

    // A different app instance has its own counter and is unaffected.
    expect((await login(second.app, user.email, "wrong-password")).status).toBe(401);
  });
});
