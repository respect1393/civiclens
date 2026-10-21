import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import request from "supertest";
import { createApp } from "../../src/app";
import { prisma } from "../../src/db";
import { createReport, createUser } from "../helpers/factory";
import { bearer, signToken } from "../helpers/token";

/**
 * A disposable upload root for this suite. Nothing here ever reads or writes
 * the developer's real `backend/uploads` directory.
 */
const uploadRoot = mkdtempSync(join(tmpdir(), "civiclens-upload-"));
const app = createApp({ uploadDir: uploadRoot });

afterAll(() => {
  rmSync(uploadRoot, { recursive: true, force: true });
});

async function tokenFor(user: { id: string; email: string; role: string }) {
  return bearer(signToken({ id: user.id, email: user.email, role: user.role }));
}

// Minimal but genuinely signature-valid images. The backend validates magic
// bytes, so these are accepted exactly like real files of each format.
const JPEG_BYTES = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46]);
const PNG_BYTES = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  Buffer.from([0x00, 0x00, 0x00, 0x0d]),
]);
const WEBP_BYTES = Buffer.concat([
  Buffer.from("RIFF"),
  Buffer.from([0x24, 0x00, 0x00, 0x00]),
  Buffer.from("WEBP"),
  Buffer.from("VP8 "),
]);

function imagePath(key: string): string {
  return join(uploadRoot, key);
}

describe("report image upload (POST /api/reports/:id/photo)", () => {
  it("stores a JPEG under a server-controlled key and records the reference", async () => {
    const { user } = await createUser({ state: "Maharashtra", district: "Pune" });
    const report = await createReport(user.id, {
      state: "Maharashtra",
      district: "Pune",
    });

    const res = await request(app)
      .post(`/api/reports/${report.id}/photo`)
      .set("Authorization", await tokenFor(user))
      .set("Content-Type", "image/jpeg")
      .send(JPEG_BYTES);

    expect(res.status).toBe(200);
    expect(res.body.id).toBe(report.id);
    expect(res.body.photoPath).toMatch(/^reports\/[a-f0-9]{64}\.jpg$/);

    const stored = await prisma.report.findUnique({ where: { id: report.id } });
    expect(stored?.photoPath).toBe(res.body.photoPath);
    expect(existsSync(imagePath(res.body.photoPath))).toBe(true);
    expect(readFileSync(imagePath(res.body.photoPath)).equals(JPEG_BYTES)).toBe(true);
  });

  it("accepts PNG and WebP signatures", async () => {
    const { user } = await createUser();
    const png = await createReport(user.id);
    const webp = await createReport(user.id);

    const pngRes = await request(app)
      .post(`/api/reports/${png.id}/photo`)
      .set("Authorization", await tokenFor(user))
      .set("Content-Type", "image/png")
      .send(PNG_BYTES);
    expect(pngRes.status).toBe(200);
    expect(pngRes.body.photoPath).toMatch(/\.png$/);

    const webpRes = await request(app)
      .post(`/api/reports/${webp.id}/photo`)
      .set("Authorization", await tokenFor(user))
      .set("Content-Type", "image/webp")
      .send(WEBP_BYTES);
    expect(webpRes.status).toBe(200);
    expect(webpRes.body.photoPath).toMatch(/\.webp$/);
  });

  it("ignores the declared content type and rejects a non-image body", async () => {
    const { user } = await createUser();
    const report = await createReport(user.id);

    const res = await request(app)
      .post(`/api/reports/${report.id}/photo`)
      .set("Authorization", await tokenFor(user))
      .set("Content-Type", "image/jpeg")
      .send(Buffer.from("this is plainly not an image"));

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Unsupported image format/i);

    const stored = await prisma.report.findUnique({ where: { id: report.id } });
    expect(stored?.photoPath).toBeNull();
  });

  it("rejects an empty body", async () => {
    const { user } = await createUser();
    const report = await createReport(user.id);

    const res = await request(app)
      .post(`/api/reports/${report.id}/photo`)
      .set("Authorization", await tokenFor(user))
      .set("Content-Type", "image/jpeg")
      .send(Buffer.alloc(0));

    expect(res.status).toBe(400);
  });

  it("rejects an image larger than the limit with 413", async () => {
    const { user } = await createUser();
    const report = await createReport(user.id);

    const oversized = Buffer.concat([JPEG_BYTES, Buffer.alloc(6 * 1024 * 1024)]);
    const res = await request(app)
      .post(`/api/reports/${report.id}/photo`)
      .set("Authorization", await tokenFor(user))
      .set("Content-Type", "image/jpeg")
      .send(oversized);

    expect(res.status).toBe(413);
  });

  it("requires authentication", async () => {
    const { user } = await createUser();
    const report = await createReport(user.id);

    const res = await request(app)
      .post(`/api/reports/${report.id}/photo`)
      .set("Content-Type", "image/jpeg")
      .send(JPEG_BYTES);

    expect(res.status).toBe(401);
  });

  it("returns 404 for an unknown report", async () => {
    const { user } = await createUser();

    const res = await request(app)
      .post("/api/reports/does-not-exist/photo")
      .set("Authorization", await tokenFor(user))
      .set("Content-Type", "image/jpeg")
      .send(JPEG_BYTES);

    expect(res.status).toBe(404);
  });

  it("forbids a non-owner, even from the same area, from attaching a photo", async () => {
    const { user: owner } = await createUser({ email: "owner@example.com" });
    const { user: other } = await createUser({ email: "other@example.com" });
    const report = await createReport(owner.id);

    const res = await request(app)
      .post(`/api/reports/${report.id}/photo`)
      .set("Authorization", await tokenFor(other))
      .set("Content-Type", "image/jpeg")
      .send(JPEG_BYTES);

    expect(res.status).toBe(403);
  });

  it("replaces the image and removes the now-unreferenced previous file", async () => {
    const { user } = await createUser();
    const report = await createReport(user.id);

    const first = await request(app)
      .post(`/api/reports/${report.id}/photo`)
      .set("Authorization", await tokenFor(user))
      .set("Content-Type", "image/jpeg")
      .send(JPEG_BYTES);
    const firstKey = first.body.photoPath as string;

    const second = await request(app)
      .post(`/api/reports/${report.id}/photo`)
      .set("Authorization", await tokenFor(user))
      .set("Content-Type", "image/png")
      .send(PNG_BYTES);
    const secondKey = second.body.photoPath as string;

    expect(secondKey).not.toBe(firstKey);
    expect(existsSync(imagePath(firstKey))).toBe(false);
    expect(existsSync(imagePath(secondKey))).toBe(true);
  });
});

describe("report image retrieval (GET /api/reports/:id/photo)", () => {
  async function uploadFor(reportId: string, user: { id: string; email: string; role: string }) {
    const res = await request(app)
      .post(`/api/reports/${reportId}/photo`)
      .set("Authorization", await tokenFor(user))
      .set("Content-Type", "image/png")
      .send(PNG_BYTES);
    expect(res.status).toBe(200);
    return res.body.photoPath as string;
  }

  it("returns the exact bytes only to an authorized viewer", async () => {
    const { user } = await createUser({ state: "Maharashtra", district: "Pune" });
    const report = await createReport(user.id, {
      state: "Maharashtra",
      district: "Pune",
    });
    await uploadFor(report.id, user);

    const res = await request(app)
      .get(`/api/reports/${report.id}/photo`)
      .set("Authorization", await tokenFor(user));

    expect(res.status).toBe(200);
    expect(res.headers["content-type"]).toContain("image/png");
    expect(res.headers["cache-control"]).toContain("private");
    expect(Buffer.isBuffer(res.body)).toBe(true);
    expect((res.body as Buffer).equals(PNG_BYTES)).toBe(true);
  });

  it("returns 401 without a token", async () => {
    const { user } = await createUser();
    const report = await createReport(user.id);
    await uploadFor(report.id, user);

    const res = await request(app).get(`/api/reports/${report.id}/photo`);
    expect(res.status).toBe(401);
  });

  it("returns 403 for a citizen from another state", async () => {
    const { user: owner } = await createUser({
      email: "img-owner@example.com",
      state: "Karnataka",
      district: "Bengaluru",
    });
    const { user: outsider } = await createUser({
      email: "img-outsider@example.com",
      state: "Maharashtra",
      district: "Pune",
    });
    const report = await createReport(owner.id, {
      state: "Karnataka",
      district: "Bengaluru",
    });
    await uploadFor(report.id, owner);

    const res = await request(app)
      .get(`/api/reports/${report.id}/photo`)
      .set("Authorization", await tokenFor(outsider));

    expect(res.status).toBe(403);
  });

  it("lets an administrator read any report image", async () => {
    const { user: owner } = await createUser({
      email: "img-owner2@example.com",
      state: "Karnataka",
      district: "Bengaluru",
    });
    const { user: admin } = await createUser({
      email: "img-admin@example.com",
      role: "ADMIN",
      state: null,
      district: null,
    });
    const report = await createReport(owner.id, {
      state: "Karnataka",
      district: "Bengaluru",
    });
    await uploadFor(report.id, owner);

    const res = await request(app)
      .get(`/api/reports/${report.id}/photo`)
      .set("Authorization", await tokenFor(admin));

    expect(res.status).toBe(200);
    expect((res.body as Buffer).equals(PNG_BYTES)).toBe(true);
  });

  it("returns 404 when the report has no image", async () => {
    const { user } = await createUser();
    const report = await createReport(user.id);

    const res = await request(app)
      .get(`/api/reports/${report.id}/photo`)
      .set("Authorization", await tokenFor(user));

    expect(res.status).toBe(404);
  });

  it("refuses a stored reference that escapes the upload root", async () => {
    const { user } = await createUser({ state: "Maharashtra", district: "Pune" });
    const report = await createReport(user.id, {
      state: "Maharashtra",
      district: "Pune",
    });
    // Simulate a corrupted/hostile stored value; retrieval must not follow it.
    await prisma.report.update({
      where: { id: report.id },
      data: { photoPath: "../../../../etc/passwd" },
    });

    const res = await request(app)
      .get(`/api/reports/${report.id}/photo`)
      .set("Authorization", await tokenFor(user));

    expect(res.status).toBe(404);
  });
});
