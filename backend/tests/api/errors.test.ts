import { describe, expect, it } from "vitest";
import request from "supertest";
import { createApp } from "../../src/app";
import { createReport, createUser } from "../helpers/factory";
import { bearer, signToken } from "../helpers/token";

const app = createApp();

async function citizenToken(state = "Maharashtra", district = "Pune") {
  const { user } = await createUser({ state, district });
  return bearer(signToken({ id: user.id, email: user.email, role: "CITIZEN" }));
}

describe("JSON 404 handler (unknown routes)", () => {
  it("returns 404 JSON for an unmatched GET route", async () => {
    const res = await request(app).get("/api/definitely-not-a-route");

    expect(res.status).toBe(404);
    expect(res.headers["content-type"]).toContain("application/json");
    expect(res.body).toEqual({ error: "Not found" });
  });

  it("returns 404 JSON for an unmatched POST route", async () => {
    const res = await request(app)
      .post("/api/also-not-a-route")
      .send({ anything: true });

    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: "Not found" });
  });

  it("returns 404 JSON for an unknown path outside /api", async () => {
    const res = await request(app).get("/nope");

    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: "Not found" });
  });
});

describe("centralized error handler", () => {
  it("returns 500 JSON without leaking the underlying error", async () => {
    // A malformed JSON body is parsed before any route handler and its error
    // reaches the global handler, which must answer with a generic 500.
    const res = await request(app)
      .post("/api/auth/login")
      .set("Content-Type", "application/json")
      .send('{"email": "oops@example.com", "password": ');

    expect(res.status).toBe(500);
    expect(res.headers["content-type"]).toContain("application/json");
    expect(res.body).toEqual({ error: "Internal server error" });
    expect(res.body).not.toHaveProperty("stack");
    expect(res.body).not.toHaveProperty("message");
    expect(res.text).not.toContain("SyntaxError");
    expect(res.text).not.toContain("at ");
  });
});

describe("existing endpoint error formats are preserved", () => {
  it("keeps 400 Invalid registration data with details", async () => {
    const res = await request(app)
      .post("/api/auth/register")
      .send({ name: "x", email: "not-an-email", password: "short" });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Invalid registration data");
    expect(res.body.details).toBeDefined();
  });

  it("keeps 400 Email already registered", async () => {
    const payload = {
      name: "Dup",
      email: "dup@example.com",
      password: "password123",
      state: "Maharashtra",
      district: "Pune",
    };
    await request(app).post("/api/auth/register").send(payload);

    const res = await request(app).post("/api/auth/register").send(payload);

    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: "Email already registered" });
  });

  it("keeps 401 Invalid credentials for a wrong password", async () => {
    const { user } = await createUser({ email: "bad.pw@example.com" });

    const res = await request(app)
      .post("/api/auth/login")
      .send({ email: user.email, password: "wrong-password" });

    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "Invalid credentials" });
  });

  it("keeps 401 Unauthorized for a missing token", async () => {
    const res = await request(app).get("/api/reports");

    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "Unauthorized" });
  });

  it("keeps 404 Report not found for an unknown report id", async () => {
    const header = await citizenToken();

    const res = await request(app)
      .get("/api/reports/does-not-exist")
      .set("Authorization", header);

    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: "Report not found" });
  });

  it("keeps 403 Forbidden for an out-of-area report", async () => {
    const readerHeader = await citizenToken("Maharashtra", "Pune");
    const { user: author } = await createUser({
      email: "far-away@example.com",
      state: "Karnataka",
      district: "Bengaluru",
    });
    const report = await createReport(author.id, {
      state: "Karnataka",
      district: "Bengaluru",
    });

    const res = await request(app)
      .get(`/api/reports/${report.id}`)
      .set("Authorization", readerHeader);

    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: "Forbidden: insufficient permissions" });
  });

  it("keeps 400 User profile incomplete for report creation", async () => {
    const { user } = await createUser({ state: null, district: null });
    const header = bearer(signToken({ id: user.id, email: user.email, role: "CITIZEN" }));

    const res = await request(app)
      .post("/api/reports")
      .set("Authorization", header)
      .send({
        title: "T",
        description: "D",
        category: "ROADS",
        area: "A",
        address: "B",
      });

    expect(res.status).toBe(400);
    expect(res.body).toEqual({
      error: "User profile incomplete: state and district required",
    });
  });

  it("keeps successful endpoints unaffected (health still 200)", async () => {
    const res = await request(app).get("/api/health");

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: "ok", service: "civiclens-backend" });
  });
});
