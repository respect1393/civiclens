import { describe, expect, it } from "vitest";
import request from "supertest";
import { createApp } from "../../src/app";
import { prisma } from "../../src/db";
import { createReport, createUser } from "../helpers/factory";
import { bearer, signToken } from "../helpers/token";

const app = createApp();

const validReport = {
  title: "Broken streetlight",
  description: "The streetlight outside number 4 has been out for a week.",
  category: "STREETLIGHTS",
  area: "Koregaon Park",
  address: "4 Lane 7, Koregaon Park",
};

async function tokenFor(user: { id: string; email: string; role: string }) {
  return bearer(signToken({ id: user.id, email: user.email, role: user.role }));
}

describe("citizen report creation (POST /api/reports)", () => {
  it("creates a report owned by the token user, ignoring a body-supplied userId", async () => {
    const { user: owner } = await createUser({
      email: "owner@example.com",
      state: "Maharashtra",
      district: "Pune",
    });
    const { user: victim } = await createUser({ email: "victim@example.com" });

    const res = await request(app)
      .post("/api/reports")
      .set("Authorization", await tokenFor(owner))
      .send({ ...validReport, userId: victim.id, state: "Karnataka", district: "Bengaluru" });

    expect(res.status).toBe(201);
    expect(res.body.userId).toBe(owner.id);
    expect(res.body.state).toBe("Maharashtra");
    expect(res.body.district).toBe("Pune");

    const stored = await prisma.report.findUnique({ where: { id: res.body.id } });
    expect(stored?.userId).toBe(owner.id);
    expect(stored?.state).toBe("Maharashtra");
    expect(stored?.district).toBe("Pune");
  });

  it("rejects an invalid category", async () => {
    const { user } = await createUser();

    const res = await request(app)
      .post("/api/reports")
      .set("Authorization", await tokenFor(user))
      .send({ ...validReport, category: "NOT_A_CATEGORY" });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Invalid report data");
    expect(res.body.details).toBeDefined();
  });

  it("rejects a payload missing required fields", async () => {
    const { user } = await createUser();

    const res = await request(app)
      .post("/api/reports")
      .set("Authorization", await tokenFor(user))
      .send({ description: "no title, category, area or address" });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Invalid report data");
  });

  it("rejects a user whose profile is missing state/district", async () => {
    const { user } = await createUser({ state: null, district: null });

    const res = await request(app)
      .post("/api/reports")
      .set("Authorization", await tokenFor(user))
      .send(validReport);

    expect(res.status).toBe(400);
    expect(res.body).toEqual({
      error: "User profile incomplete: state and district required",
    });
  });
});

describe("citizen report visibility (GET /api/reports)", () => {
  it("only lists reports from the citizen's own state and district", async () => {
    const { user: a } = await createUser({
      email: "a@example.com",
      state: "Maharashtra",
      district: "Pune",
    });
    const { user: b } = await createUser({
      email: "b@example.com",
      state: "Maharashtra",
      district: "Pune",
    });
    const { user: c } = await createUser({
      email: "c@example.com",
      state: "Karnataka",
      district: "Bengaluru",
    });

    const sameDistrict = await createReport(a.id, { state: "Maharashtra", district: "Pune" });
    const sameStateOtherDistrict = await createReport(b.id, {
      state: "Maharashtra",
      district: "Mumbai",
    });
    const otherState = await createReport(c.id, { state: "Karnataka", district: "Bengaluru" });

    const res = await request(app)
      .get("/api/reports")
      .set("Authorization", await tokenFor(a));

    expect(res.status).toBe(200);
    const ids = res.body.data.map((r: { id: string }) => r.id);
    expect(ids).toContain(sameDistrict.id);
    expect(ids).not.toContain(otherState.id);
    // District is distinct from the citizen's, so it must be hidden.
    expect(ids).not.toContain(sameStateOtherDistrict.id);
    expect(res.body.pagination.total).toBe(1);
  });

  it("shows every report in the state when the citizen has no district set", async () => {
    const { user: statewide } = await createUser({
      email: "statewide@example.com",
      state: "Maharashtra",
      district: null,
    });
    const { user: local } = await createUser({
      email: "local@example.com",
      state: "Maharashtra",
      district: "Pune",
    });
    const { user: outsider } = await createUser({
      email: "outsider@example.com",
      state: "Karnataka",
      district: "Bengaluru",
    });

    const pune = await createReport(local.id, { state: "Maharashtra", district: "Pune" });
    const mumbai = await createReport(local.id, { state: "Maharashtra", district: "Mumbai" });
    const bengaluru = await createReport(outsider.id, {
      state: "Karnataka",
      district: "Bengaluru",
    });

    const res = await request(app)
      .get("/api/reports")
      .set("Authorization", await tokenFor(statewide));

    expect(res.status).toBe(200);
    const ids = res.body.data.map((r: { id: string }) => r.id);
    expect(ids).toEqual(expect.arrayContaining([pune.id, mumbai.id]));
    expect(ids).not.toContain(bengaluru.id);
    expect(res.body.pagination.total).toBe(2);
  });

  it("clamps pagination parameters", async () => {
    const { user } = await createUser({ state: "Maharashtra", district: "Pune" });
    for (let i = 0; i < 3; i++) {
      await createReport(user.id, { state: "Maharashtra", district: "Pune" });
    }

    const res = await request(app)
      .get("/api/reports?page=0&limit=2")
      .set("Authorization", await tokenFor(user));

    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(2);
    expect(res.body.pagination).toMatchObject({ page: 1, limit: 2, total: 3, totalPages: 2 });
  });

  it("returns no reports for a citizen whose state is missing", async () => {
    const { user: stateless } = await createUser({
      email: "stateless@example.com",
      state: null,
      district: null,
    });
    const { user: located } = await createUser({
      email: "located@example.com",
      state: "Maharashtra",
      district: "Pune",
    });

    // Seed reports, including one whose state is NULL, to prove none leak to a
    // citizen without a state.
    await createReport(located.id, { state: null, district: null });
    await createReport(located.id, { state: "Maharashtra", district: "Pune" });

    const res = await request(app)
      .get("/api/reports")
      .set("Authorization", await tokenFor(stateless));

    expect(res.status).toBe(200);
    expect(res.body.data).toEqual([]);
    expect(res.body.pagination.total).toBe(0);
  });
});

describe("citizen single-report access (GET /api/reports/:id)", () => {
  it("returns a report in the citizen's own state and district", async () => {
    const { user } = await createUser({ state: "Maharashtra", district: "Pune" });
    const report = await createReport(user.id, { state: "Maharashtra", district: "Pune" });

    const res = await request(app)
      .get(`/api/reports/${report.id}`)
      .set("Authorization", await tokenFor(user));

    expect(res.status).toBe(200);
    expect(res.body.id).toBe(report.id);
  });

  it("forbids access to a report from another district", async () => {
    const { user: reader } = await createUser({
      email: "reader@example.com",
      state: "Maharashtra",
      district: "Pune",
    });
    const { user: author } = await createUser({
      email: "author@example.com",
      state: "Maharashtra",
      district: "Mumbai",
    });
    const report = await createReport(author.id, { state: "Maharashtra", district: "Mumbai" });

    const res = await request(app)
      .get(`/api/reports/${report.id}`)
      .set("Authorization", await tokenFor(reader));

    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: "Forbidden: insufficient permissions" });
  });

  it("forbids access to a report from another state", async () => {
    const { user: reader } = await createUser({
      email: "reader2@example.com",
      state: "Maharashtra",
      district: "Pune",
    });
    const { user: author } = await createUser({
      email: "author2@example.com",
      state: "Karnataka",
      district: "Bengaluru",
    });
    const report = await createReport(author.id, {
      state: "Karnataka",
      district: "Bengaluru",
    });

    const res = await request(app)
      .get(`/api/reports/${report.id}`)
      .set("Authorization", await tokenFor(reader));

    expect(res.status).toBe(403);
  });

  it("returns 404 for an unknown report id", async () => {
    const { user } = await createUser({ state: "Maharashtra", district: "Pune" });

    const res = await request(app)
      .get("/api/reports/does-not-exist")
      .set("Authorization", await tokenFor(user));

    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: "Report not found" });
  });
});
