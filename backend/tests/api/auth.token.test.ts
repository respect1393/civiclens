import { describe, expect, it } from "vitest";
import request from "supertest";
import { createApp } from "../../src/app";
import { createReport, createUser } from "../helpers/factory";
import { bearer, signToken, signWithSecret } from "../helpers/token";

const app = createApp();

// GET /api/reports is protected by the authenticate middleware.
const PROTECTED_PATH = "/api/reports";

describe("authenticate middleware (via GET /api/reports)", () => {
  it("rejects a request with no Authorization header", async () => {
    const res = await request(app).get(PROTECTED_PATH);

    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "Unauthorized" });
  });

  it("rejects a non-Bearer scheme", async () => {
    const { user } = await createUser();
    const token = signToken({ id: user.id, email: user.email, role: "CITIZEN" });

    const res = await request(app)
      .get(PROTECTED_PATH)
      .set("Authorization", `Token ${token}`);

    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "Unauthorized" });
  });

  it("rejects a Bearer header with an empty token", async () => {
    const res = await request(app)
      .get(PROTECTED_PATH)
      .set("Authorization", "Bearer ");

    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "Unauthorized" });
  });

  it("rejects a malformed token", async () => {
    const res = await request(app)
      .get(PROTECTED_PATH)
      .set("Authorization", "Bearer not.a.jwt");

    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "Unauthorized" });
  });

  it("rejects a token signed with the wrong secret", async () => {
    const { user } = await createUser();
    const forged = signWithSecret(
      { id: user.id, email: user.email, role: "ADMIN" },
      "a-completely-different-secret-value-000000",
      { expiresIn: "7d" }
    );

    const res = await request(app)
      .get(PROTECTED_PATH)
      .set("Authorization", bearer(forged));

    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "Unauthorized" });
  });

  it("rejects a token signed with a non-HS256 algorithm", async () => {
    const { user } = await createUser();
    const hs384 = signToken(
      { id: user.id, email: user.email, role: "CITIZEN" },
      { algorithm: "HS384" }
    );

    const res = await request(app)
      .get(PROTECTED_PATH)
      .set("Authorization", bearer(hs384));

    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "Unauthorized" });
  });

  it("rejects an expired token", async () => {
    const { user } = await createUser();
    const expired = signToken(
      { id: user.id, email: user.email, role: "CITIZEN" },
      { expiresIn: "-10s" }
    );

    const res = await request(app)
      .get(PROTECTED_PATH)
      .set("Authorization", bearer(expired));

    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "Unauthorized" });
  });

  it("rejects a validly-signed token whose user no longer exists", async () => {
    const token = signToken({
      id: "cm-deleted-user-does-not-exist",
      email: "ghost@example.com",
      role: "CITIZEN",
    });

    const res = await request(app)
      .get(PROTECTED_PATH)
      .set("Authorization", bearer(token));

    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "Unauthorized" });
  });

  it("accepts a valid token and returns the paginated envelope", async () => {
    const { user } = await createUser();
    const token = signToken({ id: user.id, email: user.email, role: "CITIZEN" });

    const res = await request(app)
      .get(PROTECTED_PATH)
      .set("Authorization", bearer(token));

    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.data)).toBe(true);
    expect(res.body.pagination).toMatchObject({ page: 1, limit: 20 });
  });

  it("trusts the database role, not the role embedded in the token", async () => {
    // An administrator whose token falsely claims CITIZEN must still be treated
    // as an administrator, because the middleware reloads the user from the DB.
    const { user: admin } = await createUser({
      email: "db-role-admin@example.com",
      role: "ADMIN",
      state: "Maharashtra",
      district: "Pune",
    });
    const { user: other } = await createUser({
      email: "other@example.com",
      state: "Karnataka",
      district: "Bengaluru",
    });
    await createReport(admin.id, { state: "Maharashtra", district: "Pune" });
    await createReport(other.id, { state: "Karnataka", district: "Bengaluru" });

    const liarToken = signToken({
      id: admin.id,
      email: admin.email,
      role: "CITIZEN",
    });

    const res = await request(app)
      .get(PROTECTED_PATH)
      .set("Authorization", bearer(liarToken));

    expect(res.status).toBe(200);
    // Administrators see only their own state's reports, not every report.
    expect(res.body.pagination.total).toBe(1);
  });
});
