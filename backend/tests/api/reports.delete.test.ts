import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import request from "supertest";
import { createApp } from "../../src/app";
import { prisma } from "../../src/db";
import { createReport, createUser } from "../helpers/factory";
import { bearer, signToken } from "../helpers/token";

const uploadRoot = mkdtempSync(join(tmpdir(), "civiclens-delete-"));
const app = createApp({ uploadDir: uploadRoot });

afterAll(() => {
  rmSync(uploadRoot, { recursive: true, force: true });
});

const PNG_BYTES = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  Buffer.from([0x00, 0x00, 0x00, 0x0d]),
]);

async function tokenFor(user: { id: string; email: string; role: string }) {
  return bearer(signToken({ id: user.id, email: user.email, role: user.role }));
}

async function attachPhoto(reportId: string, user: { id: string; email: string; role: string }) {
  const res = await request(app)
    .post(`/api/reports/${reportId}/photo`)
    .set("Authorization", await tokenFor(user))
    .set("Content-Type", "image/png")
    .send(PNG_BYTES);
  expect(res.status).toBe(200);
  return res.body.photoPath as string;
}

describe("report deletion (DELETE /api/reports/:id)", () => {
  it("deletes the caller's own report and cascades to history and notes", async () => {
    const { user: owner } = await createUser({ state: "Maharashtra", district: "Pune" });
    const { user: admin } = await createUser({ email: "note-admin@example.com", role: "ADMIN" });
    const report = await createReport(owner.id, {
      state: "Maharashtra",
      district: "Pune",
    });
    await prisma.statusHistory.create({
      data: { reportId: report.id, newStatus: "UNDER_REVIEW" },
    });
    await prisma.adminNote.create({
      data: { reportId: report.id, adminId: admin.id, content: "Looking into it" },
    });

    const res = await request(app)
      .delete(`/api/reports/${report.id}`)
      .set("Authorization", await tokenFor(owner));

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ id: report.id, deleted: true, imageDeleted: false });

    expect(await prisma.report.findUnique({ where: { id: report.id } })).toBeNull();
    expect(await prisma.statusHistory.count({ where: { reportId: report.id } })).toBe(0);
    expect(await prisma.adminNote.count({ where: { reportId: report.id } })).toBe(0);
  });

  it("deletes the associated image when it becomes unreferenced", async () => {
    const { user } = await createUser();
    const report = await createReport(user.id);
    const key = await attachPhoto(report.id, user);
    expect(existsSync(join(uploadRoot, key))).toBe(true);

    const res = await request(app)
      .delete(`/api/reports/${report.id}`)
      .set("Authorization", await tokenFor(user));

    expect(res.status).toBe(200);
    expect(res.body.imageDeleted).toBe(true);
    expect(existsSync(join(uploadRoot, key))).toBe(false);
  });

  it("keeps an image that another report still references", async () => {
    const { user } = await createUser();
    const first = await createReport(user.id);
    const second = await createReport(user.id);

    // Identical bytes produce the same content-addressed key, so both reports
    // legitimately share one file.
    const keyA = await attachPhoto(first.id, user);
    const keyB = await attachPhoto(second.id, user);
    expect(keyA).toBe(keyB);

    const deleteFirst = await request(app)
      .delete(`/api/reports/${first.id}`)
      .set("Authorization", await tokenFor(user));
    expect(deleteFirst.status).toBe(200);
    expect(deleteFirst.body.imageDeleted).toBe(false);
    expect(existsSync(join(uploadRoot, keyA))).toBe(true);

    const deleteSecond = await request(app)
      .delete(`/api/reports/${second.id}`)
      .set("Authorization", await tokenFor(user));
    expect(deleteSecond.status).toBe(200);
    expect(deleteSecond.body.imageDeleted).toBe(true);
    expect(existsSync(join(uploadRoot, keyA))).toBe(false);
  });

  it("forbids deleting someone else's report", async () => {
    const { user: owner } = await createUser({ email: "del-owner@example.com" });
    const { user: other } = await createUser({ email: "del-other@example.com" });
    const report = await createReport(owner.id);

    const res = await request(app)
      .delete(`/api/reports/${report.id}`)
      .set("Authorization", await tokenFor(other));

    expect(res.status).toBe(403);
    // The report must still exist.
    expect(await prisma.report.findUnique({ where: { id: report.id } })).not.toBeNull();
  });

  it("does not let an administrator delete a report they do not own", async () => {
    const { user: owner } = await createUser({ email: "del-owner2@example.com" });
    const { user: admin } = await createUser({
      email: "del-admin@example.com",
      role: "ADMIN",
    });
    const report = await createReport(owner.id);

    const res = await request(app)
      .delete(`/api/reports/${report.id}`)
      .set("Authorization", await tokenFor(admin));

    expect(res.status).toBe(403);
    expect(await prisma.report.findUnique({ where: { id: report.id } })).not.toBeNull();
  });

  it("requires authentication", async () => {
    const { user } = await createUser();
    const report = await createReport(user.id);

    const res = await request(app).delete(`/api/reports/${report.id}`);

    expect(res.status).toBe(401);
    expect(await prisma.report.findUnique({ where: { id: report.id } })).not.toBeNull();
  });

  it("returns 404 for an unknown report", async () => {
    const { user } = await createUser();

    const res = await request(app)
      .delete("/api/reports/does-not-exist")
      .set("Authorization", await tokenFor(user));

    expect(res.status).toBe(404);
  });
});
