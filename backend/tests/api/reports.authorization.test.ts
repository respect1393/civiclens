import { describe, expect, it } from "vitest";
import request from "supertest";
import { createApp } from "../../src/app";
import { prisma } from "../../src/db";
import { createReport, createUser } from "../helpers/factory";
import { bearer, signToken } from "../helpers/token";

const app = createApp();

async function tokenFor(user: { id: string; email: string; role: string }) {
  return bearer(signToken({ id: user.id, email: user.email, role: user.role }));
}

const validReport = {
  title: "Broken streetlight",
  description: "The streetlight outside number 4 has been out for a week.",
  category: "STREETLIGHTS",
  area: "Koregaon Park",
  address: "4 Lane 7, Koregaon Park",
};

describe("My Reports — ownership filtering (GET /api/reports?mine=true)", () => {
  it("a citizen receives only their own reports", async () => {
    const { user: owner } = await createUser({
      email: "owner@example.com",
      state: "Maharashtra",
      district: "Pune",
    });
    const { user: other } = await createUser({
      email: "other@example.com",
      state: "Maharashtra",
      district: "Pune",
    });

    const ownReport = await createReport(owner.id, {
      state: "Maharashtra",
      district: "Pune",
    });
    await createReport(other.id, { state: "Maharashtra", district: "Pune" });

    const res = await request(app)
      .get("/api/reports?mine=true")
      .set("Authorization", await tokenFor(owner));

    expect(res.status).toBe(200);
    const ids = res.body.data.map((r: { id: string }) => r.id);
    expect(ids).toContain(ownReport.id);
    expect(ids).not.toContain(expect.any(String));
    expect(res.body.pagination.total).toBe(1);
  });

  it("an administrator receives only their own reports", async () => {
    const { user: admin } = await createUser({
      email: "admin1@example.com",
      role: "ADMIN",
      state: "Maharashtra",
      district: "Pune",
    });
    const { user: otherAdmin } = await createUser({
      email: "admin2@example.com",
      role: "ADMIN",
      state: "Maharashtra",
      district: "Pune",
    });

    const ownReport = await createReport(admin.id, {
      state: "Maharashtra",
      district: "Pune",
    });
    await createReport(otherAdmin.id, {
      state: "Maharashtra",
      district: "Pune",
    });

    const res = await request(app)
      .get("/api/reports?mine=true")
      .set("Authorization", await tokenFor(admin));

    expect(res.status).toBe(200);
    const ids = res.body.data.map((r: { id: string }) => r.id);
    expect(ids).toContain(ownReport.id);
    expect(ids).not.toContain(expect.any(String));
    expect(res.body.pagination.total).toBe(1);
  });

  it("an administrator cannot see another administrator's reports through My Reports", async () => {
    const { user: admin1 } = await createUser({
      email: "admin1@example.com",
      role: "ADMIN",
      state: "Maharashtra",
      district: "Pune",
    });
    const { user: admin2 } = await createUser({
      email: "admin2@example.com",
      role: "ADMIN",
      state: "Maharashtra",
      district: "Pune",
    });

    await createReport(admin1.id, { state: "Maharashtra", district: "Pune" });
    const admin2Report = await createReport(admin2.id, {
      state: "Maharashtra",
      district: "Pune",
    });

    const res = await request(app)
      .get("/api/reports?mine=true")
      .set("Authorization", await tokenFor(admin1));

    expect(res.status).toBe(200);
    const ids = res.body.data.map((r: { id: string }) => r.id);
    expect(ids).not.toContain(admin2Report.id);
    expect(res.body.pagination.total).toBe(1);
  });

  it("client-supplied userId cannot override ownership filtering", async () => {
    const { user: owner } = await createUser({
      email: "owner@example.com",
      state: "Maharashtra",
      district: "Pune",
    });
    const { user: victim } = await createUser({
      email: "victim@example.com",
      state: "Maharashtra",
      district: "Pune",
    });

    await createReport(victim.id, { state: "Maharashtra", district: "Pune" });

    // Attempt to override ownership via query parameter (should be ignored).
    const res = await request(app)
      .get(`/api/reports?mine=true&userId=${victim.id}`)
      .set("Authorization", await tokenFor(owner));

    expect(res.status).toBe(200);
    const ids = res.body.data.map((r: { id: string }) => r.id);
    expect(ids).toHaveLength(0);
  });
});

describe("Explore — citizen district-based filtering (GET /api/reports)", () => {
  it("a citizen's default results are limited to their registered district", async () => {
    const { user } = await createUser({
      email: "citizen@example.com",
      state: "Maharashtra",
      district: "Pune",
    });

    const pune = await createReport(user.id, {
      state: "Maharashtra",
      district: "Pune",
    });
    await createReport(user.id, {
      state: "Maharashtra",
      district: "Mumbai",
    });

    const res = await request(app)
      .get("/api/reports")
      .set("Authorization", await tokenFor(user));

    expect(res.status).toBe(200);
    const ids = res.body.data.map((r: { id: string }) => r.id);
    expect(ids).toContain(pune.id);
    expect(ids).toHaveLength(1);
    expect(res.body.pagination.total).toBe(1);
  });

  it("a citizen can explore another district within their own state", async () => {
    const { user } = await createUser({
      email: "citizen@example.com",
      state: "Maharashtra",
      district: "Pune",
    });

    const mumbai = await createReport(user.id, {
      state: "Maharashtra",
      district: "Mumbai",
    });

    const res = await request(app)
      .get("/api/reports?district=Mumbai")
      .set("Authorization", await tokenFor(user));

    expect(res.status).toBe(200);
    const ids = res.body.data.map((r: { id: string }) => r.id);
    expect(ids).toContain(mumbai.id);
    expect(res.body.pagination.total).toBe(1);
  });

  it("a citizen cannot access another state's reports via district parameter", async () => {
    const { user } = await createUser({
      email: "citizen@example.com",
      state: "Maharashtra",
      district: "Pune",
    });
    const { user: outsider } = await createUser({
      email: "outsider@example.com",
      state: "Karnataka",
      district: "Bengaluru",
    });

    const bengaluru = await createReport(outsider.id, {
      state: "Karnataka",
      district: "Bengaluru",
    });

    const res = await request(app)
      .get("/api/reports?district=Bengaluru")
      .set("Authorization", await tokenFor(user));

    expect(res.status).toBe(200);
    const ids = res.body.data.map((r: { id: string }) => r.id);
    expect(ids).not.toContain(bengaluru.id);
    expect(res.body.pagination.total).toBe(0);
  });

  it("missing geographic information does not cause unrestricted access", async () => {
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

    await createReport(located.id, { state: "Maharashtra", district: "Pune" });

    const res = await request(app)
      .get("/api/reports")
      .set("Authorization", await tokenFor(stateless));

    expect(res.status).toBe(200);
    expect(res.body.data).toEqual([]);
    expect(res.body.pagination.total).toBe(0);
  });
});

describe("Admin Dashboard — state-level access (GET /api/reports)", () => {
  it("an administrator can see reports across all districts in their registered state", async () => {
    const { user: admin } = await createUser({
      email: "admin@example.com",
      role: "ADMIN",
      state: "Maharashtra",
      district: "Pune",
    });

    const pune = await createReport(admin.id, {
      state: "Maharashtra",
      district: "Pune",
    });
    const mumbai = await createReport(admin.id, {
      state: "Maharashtra",
      district: "Mumbai",
    });

    const res = await request(app)
      .get("/api/reports")
      .set("Authorization", await tokenFor(admin));

    expect(res.status).toBe(200);
    const ids = res.body.data.map((r: { id: string }) => r.id);
    expect(ids).toContain(pune.id);
    expect(ids).toContain(mumbai.id);
    expect(res.body.pagination.total).toBe(2);
  });

  it("an administrator cannot see another state's reports", async () => {
    const { user: adminA } = await createUser({
      email: "adminA@example.com",
      role: "ADMIN",
      state: "Maharashtra",
      district: "Pune",
    });
    const { user: adminB } = await createUser({
      email: "adminB@example.com",
      role: "ADMIN",
      state: "Karnataka",
      district: "Bengaluru",
    });

    await createReport(adminA.id, { state: "Maharashtra", district: "Pune" });
    const bengaluru = await createReport(adminB.id, {
      state: "Karnataka",
      district: "Bengaluru",
    });

    const res = await request(app)
      .get("/api/reports")
      .set("Authorization", await tokenFor(adminA));

    expect(res.status).toBe(200);
    const ids = res.body.data.map((r: { id: string }) => r.id);
    expect(ids).not.toContain(bengaluru.id);
    expect(res.body.pagination.total).toBe(1);
  });

  it("an administrator cannot bypass restrictions by requesting a report directly by ID", async () => {
    const { user: adminA } = await createUser({
      email: "adminA@example.com",
      role: "ADMIN",
      state: "Maharashtra",
      district: "Pune",
    });
    const { user: adminB } = await createUser({
      email: "adminB@example.com",
      role: "ADMIN",
      state: "Karnataka",
      district: "Bengaluru",
    });

    const bengaluru = await createReport(adminB.id, {
      state: "Karnataka",
      district: "Bengaluru",
    });

    const res = await request(app)
      .get(`/api/reports/${bengaluru.id}`)
      .set("Authorization", await tokenFor(adminA));

    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: "Forbidden: insufficient permissions" });
  });

  it("administrative totals and pagination respect state boundaries", async () => {
    const { user: admin } = await createUser({
      email: "admin@example.com",
      role: "ADMIN",
      state: "Maharashtra",
      district: "Pune",
    });
    const { user: otherStateAdmin } = await createUser({
      email: "other@example.com",
      role: "ADMIN",
      state: "Karnataka",
      district: "Bengaluru",
    });

    await createReport(admin.id, { state: "Maharashtra", district: "Pune" });
    await createReport(admin.id, { state: "Maharashtra", district: "Mumbai" });
    await createReport(otherStateAdmin.id, {
      state: "Karnataka",
      district: "Bengaluru",
    });

    const res = await request(app)
      .get("/api/reports?page=1&limit=5")
      .set("Authorization", await tokenFor(admin));

    expect(res.status).toBe(200);
    expect(res.body.pagination.total).toBe(2);
    expect(res.body.pagination.totalPages).toBe(1);
    const ids = res.body.data.map((r: { id: string }) => r.id);
    expect(ids).toHaveLength(2);
  });

  it("an administrator without a state sees no reports", async () => {
    const { user: statelessAdmin } = await createUser({
      email: "stateless@example.com",
      role: "ADMIN",
      state: null,
      district: null,
    });

    const res = await request(app)
      .get("/api/reports")
      .set("Authorization", await tokenFor(statelessAdmin));

    expect(res.status).toBe(200);
    expect(res.body.data).toEqual([]);
    expect(res.body.pagination.total).toBe(0);
  });
});

describe("Admin report-management — state boundary enforcement", () => {
  it("an administrator cannot update a report status outside their state", async () => {
    const { user: adminA } = await createUser({
      email: "adminA@example.com",
      role: "ADMIN",
      state: "Maharashtra",
      district: "Pune",
    });
    const { user: adminB } = await createUser({
      email: "adminB@example.com",
      role: "ADMIN",
      state: "Karnataka",
      district: "Bengaluru",
    });

    const bengaluru = await createReport(adminB.id, {
      state: "Karnataka",
      district: "Bengaluru",
    });

    const res = await request(app)
      .patch(`/api/reports/${bengaluru.id}/status`)
      .set("Authorization", await tokenFor(adminA))
      .send({ status: "RESOLVED" });

    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: "Forbidden: insufficient permissions" });

    // Verify the status was not changed.
    const stored = await prisma.report.findUnique({
      where: { id: bengaluru.id },
      select: { status: true },
    });
    expect(stored?.status).toBe("SUBMITTED");
  });

  it("an administrator cannot add a note to a report outside their state", async () => {
    const { user: adminA } = await createUser({
      email: "adminA@example.com",
      role: "ADMIN",
      state: "Maharashtra",
      district: "Pune",
    });
    const { user: adminB } = await createUser({
      email: "adminB@example.com",
      role: "ADMIN",
      state: "Karnataka",
      district: "Bengaluru",
    });

    const bengaluru = await createReport(adminB.id, {
      state: "Karnataka",
      district: "Bengaluru",
    });

    const res = await request(app)
      .post(`/api/reports/${bengaluru.id}/notes`)
      .set("Authorization", await tokenFor(adminA))
      .send({ content: "Cross-state note attempt" });

    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: "Forbidden: insufficient permissions" });

    // Verify no note was created.
    const count = await prisma.adminNote.count({
      where: { reportId: bengaluru.id },
    });
    expect(count).toBe(0);
  });
});
