import { describe, expect, it } from "vitest";
import request from "supertest";
import { createApp } from "../../src/app";
import { prisma } from "../../src/db";
import { createReport, createUser } from "../helpers/factory";
import { bearer, signToken } from "../helpers/token";

const app = createApp();

async function createAdmin() {
  const { user } = await createUser({
    email: `admin-${Math.random().toString(36).slice(2)}@example.com`,
    role: "ADMIN",
    state: null,
    district: null,
  });
  return {
    user,
    header: bearer(signToken({ id: user.id, email: user.email, role: "ADMIN" })),
  };
}

async function createCitizen() {
  const { user } = await createUser({
    email: `citizen-${Math.random().toString(36).slice(2)}@example.com`,
    state: "Maharashtra",
    district: "Pune",
  });
  return {
    user,
    header: bearer(signToken({ id: user.id, email: user.email, role: "CITIZEN" })),
  };
}

describe("PATCH /api/reports/:id/status", () => {
  it("requires authentication", async () => {
    const { user } = await createCitizen();
    const report = await createReport(user.id);

    const res = await request(app)
      .patch(`/api/reports/${report.id}/status`)
      .send({ status: "UNDER_REVIEW" });

    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "Unauthorized" });
  });

  it("forbids a citizen from changing status", async () => {
    const { user, header } = await createCitizen();
    const report = await createReport(user.id);

    const res = await request(app)
      .patch(`/api/reports/${report.id}/status`)
      .set("Authorization", header)
      .send({ status: "RESOLVED" });

    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: "Forbidden: insufficient permissions" });

    const unchanged = await prisma.report.findUnique({ where: { id: report.id } });
    expect(unchanged?.status).toBe("SUBMITTED");
  });

  it("rejects an invalid status value", async () => {
    const { header } = await createAdmin();
    const { user } = await createCitizen();
    const report = await createReport(user.id);

    const res = await request(app)
      .patch(`/api/reports/${report.id}/status`)
      .set("Authorization", header)
      .send({ status: "DONE" });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Invalid status update data");
  });

  it("returns 404 for an unknown report", async () => {
    const { header } = await createAdmin();

    const res = await request(app)
      .patch("/api/reports/does-not-exist/status")
      .set("Authorization", header)
      .send({ status: "RESOLVED" });

    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: "Report not found" });
  });

  it("updates the status and writes a matching history row atomically", async () => {
    const { header } = await createAdmin();
    const { user } = await createCitizen();
    const report = await createReport(user.id);

    const res = await request(app)
      .patch(`/api/reports/${report.id}/status`)
      .set("Authorization", header)
      .send({ status: "IN_PROGRESS" });

    expect(res.status).toBe(200);
    expect(res.body.status).toBe("IN_PROGRESS");
    expect(res.body.statusHistory).toHaveLength(1);
    expect(res.body.statusHistory[0]).toMatchObject({
      reportId: report.id,
      oldStatus: "SUBMITTED",
      newStatus: "IN_PROGRESS",
    });

    const history = await prisma.statusHistory.findMany({
      where: { reportId: report.id },
    });
    expect(history).toHaveLength(1);
    expect(history[0].oldStatus).toBe("SUBMITTED");
    expect(history[0].newStatus).toBe("IN_PROGRESS");
  });

  it("does not append a duplicate history entry when the status is unchanged", async () => {
    const { header } = await createAdmin();
    const { user } = await createCitizen();
    const report = await createReport(user.id);

    const res = await request(app)
      .patch(`/api/reports/${report.id}/status`)
      .set("Authorization", header)
      .send({ status: "SUBMITTED" });

    expect(res.status).toBe(200);
    expect(res.body.status).toBe("SUBMITTED");

    const history = await prisma.statusHistory.count({
      where: { reportId: report.id },
    });
    expect(history).toBe(0);
  });
});

describe("POST /api/reports/:id/notes", () => {
  it("requires authentication", async () => {
    const { user } = await createCitizen();
    const report = await createReport(user.id);

    const res = await request(app)
      .post(`/api/reports/${report.id}/notes`)
      .send({ content: "Field crew dispatched." });

    expect(res.status).toBe(401);
  });

  it("forbids a citizen from creating a note", async () => {
    const { user, header } = await createCitizen();
    const report = await createReport(user.id);

    const res = await request(app)
      .post(`/api/reports/${report.id}/notes`)
      .set("Authorization", header)
      .send({ content: "Trying to write an internal note." });

    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: "Forbidden: insufficient permissions" });

    expect(await prisma.adminNote.count()).toBe(0);
  });

  it("rejects empty note content", async () => {
    const { header } = await createAdmin();
    const { user } = await createCitizen();
    const report = await createReport(user.id);

    const res = await request(app)
      .post(`/api/reports/${report.id}/notes`)
      .set("Authorization", header)
      .send({ content: "   " });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Invalid note data");
  });

  it("returns 404 for an unknown report without writing anything", async () => {
    const { header } = await createAdmin();

    const res = await request(app)
      .post("/api/reports/missing/notes")
      .set("Authorization", header)
      .send({ content: "Note on a missing report." });

    expect(res.status).toBe(404);
    expect(await prisma.adminNote.count()).toBe(0);
  });

  it("persists the note with the authenticated administrator's id", async () => {
    const { user: admin, header } = await createAdmin();
    const { user } = await createCitizen();
    const report = await createReport(user.id);

    const res = await request(app)
      .post(`/api/reports/${report.id}/notes`)
      .set("Authorization", header)
      .send({ content: "Inspection scheduled for Friday." });

    expect(res.status).toBe(201);
    expect(res.body).toMatchObject({
      reportId: report.id,
      content: "Inspection scheduled for Friday.",
      adminId: admin.id,
    });
    expect(res.body.admin).toMatchObject({ id: admin.id, name: "Test User" });

    const stored = await prisma.adminNote.findUnique({ where: { id: res.body.id } });
    expect(stored?.adminId).toBe(admin.id);
    expect(stored?.content).toBe("Inspection scheduled for Friday.");
  });
});

describe("administrative detail includes are admin-only", () => {
  it("returns status history and notes to an administrator on GET /:id", async () => {
    const { user: admin, header } = await createAdmin();
    const { user } = await createCitizen();
    const report = await createReport(user.id);

    await request(app)
      .patch(`/api/reports/${report.id}/status`)
      .set("Authorization", header)
      .send({ status: "UNDER_REVIEW" });
    await request(app)
      .post(`/api/reports/${report.id}/notes`)
      .set("Authorization", header)
      .send({ content: "Internal triage note." });

    const res = await request(app)
      .get(`/api/reports/${report.id}`)
      .set("Authorization", header);

    expect(res.status).toBe(200);
    expect(res.body.statusHistory).toHaveLength(1);
    expect(res.body.adminNotes).toHaveLength(1);
    expect(res.body.adminNotes[0].content).toBe("Internal triage note.");
    expect(res.body.adminNotes[0].admin.id).toBe(admin.id);
  });

  it("never exposes admin notes or history to a citizen viewer", async () => {
    const { header: adminHeader } = await createAdmin();
    const { user, header } = await createCitizen();
    const report = await createReport(user.id);

    await request(app)
      .post(`/api/reports/${report.id}/notes`)
      .set("Authorization", adminHeader)
      .send({ content: "Do not share with the reporter." });

    const detail = await request(app)
      .get(`/api/reports/${report.id}`)
      .set("Authorization", header);

    expect(detail.status).toBe(200);
    expect(detail.body).not.toHaveProperty("adminNotes");
    expect(detail.body).not.toHaveProperty("statusHistory");

    const list = await request(app).get("/api/reports").set("Authorization", header);
    expect(list.status).toBe(200);
    expect(list.body.data[0]).not.toHaveProperty("adminNotes");
    expect(list.body.data[0]).not.toHaveProperty("statusHistory");
  });

  it("includes status history and notes in the administrator list", async () => {
    const { header } = await createAdmin();
    const { user } = await createCitizen();
    const report = await createReport(user.id);

    await request(app)
      .post(`/api/reports/${report.id}/notes`)
      .set("Authorization", header)
      .send({ content: "Listed note." });

    const res = await request(app).get("/api/reports").set("Authorization", header);

    expect(res.status).toBe(200);
    const row = res.body.data.find((r: { id: string }) => r.id === report.id);
    expect(row.adminNotes).toHaveLength(1);
    expect(Array.isArray(row.statusHistory)).toBe(true);
  });
});
