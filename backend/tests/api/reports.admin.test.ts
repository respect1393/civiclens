import { describe, expect, it } from "vitest";
import request from "supertest";
import { createApp } from "../../src/app";
import { createReport, createUser } from "../helpers/factory";
import { bearer, signToken } from "../helpers/token";

const app = createApp();

async function adminToken() {
  const { user } = await createUser({
    email: "admin@example.com",
    role: "ADMIN",
    state: "Maharashtra",
    district: "Pune",
  });
  return { user, header: bearer(signToken({ id: user.id, email: user.email, role: "ADMIN" })) };
}

describe("administrator report access", () => {
  it("lists reports across every district in their registered state", async () => {
    const { header } = await adminToken();
    const { user: a } = await createUser({ email: "a@example.com", state: "Maharashtra", district: "Pune" });
    const { user: b } = await createUser({ email: "b@example.com", state: "Maharashtra", district: "Mumbai" });
    const { user: c } = await createUser({ email: "c@example.com", state: "Karnataka", district: "Bengaluru" });

    const r1 = await createReport(a.id, { state: "Maharashtra", district: "Pune" });
    const r2 = await createReport(b.id, { state: "Maharashtra", district: "Mumbai" });
    const r3 = await createReport(c.id, { state: "Karnataka", district: "Bengaluru" });

    const res = await request(app).get("/api/reports").set("Authorization", header);

    expect(res.status).toBe(200);
    const ids = res.body.data.map((r: { id: string }) => r.id);
    expect(ids).toContain(r1.id);
    expect(ids).toContain(r2.id);
    expect(ids).not.toContain(r3.id);
    expect(res.body.pagination.total).toBe(2);
  });

  it("can read a report by id within their registered state", async () => {
    const { header } = await adminToken();
    const { user: author } = await createUser({
      email: "author@example.com",
      state: "Maharashtra",
      district: "Pune",
    });
    const report = await createReport(author.id, { state: "Maharashtra", district: "Pune" });

    const res = await request(app)
      .get(`/api/reports/${report.id}`)
      .set("Authorization", header);

    expect(res.status).toBe(200);
    expect(res.body.id).toBe(report.id);
  });

  it("cannot read a report by id outside their registered state", async () => {
    const { header } = await adminToken();
    const { user: author } = await createUser({
      email: "author@example.com",
      state: "Karnataka",
      district: "Bengaluru",
    });
    const report = await createReport(author.id, { state: "Karnataka", district: "Bengaluru" });

    const res = await request(app)
      .get(`/api/reports/${report.id}`)
      .set("Authorization", header);

    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: "Forbidden: insufficient permissions" });
  });

  it("CHARACTERIZATION: an admin without state/district cannot create a report", async () => {
    // Administrators are seeded with null geography and report creation forces
    // the creator's geography, so an admin gets the incomplete-profile 400.
    const { user: admin } = await createUser({
      email: "stateless-admin@example.com",
      role: "ADMIN",
      state: null,
      district: null,
    });
    const header = bearer(signToken({ id: admin.id, email: admin.email, role: "ADMIN" }));

    const res = await request(app)
      .post("/api/reports")
      .set("Authorization", header)
      .send({
        title: "Admin-created report",
        description: "Attempt by an administrator with no state/district.",
        category: "ROADS",
        area: "Area",
        address: "Address",
      });

    expect(res.status).toBe(400);
    expect(res.body).toEqual({
      error: "User profile incomplete: state and district required",
    });
  });

  it("can create a report when the admin has a state and district", async () => {
    const { user } = await createUser({
      email: "regional-admin@example.com",
      role: "ADMIN",
      state: "Maharashtra",
      district: "Pune",
    });
    const header = bearer(signToken({ id: user.id, email: user.email, role: "ADMIN" }));

    const res = await request(app)
      .post("/api/reports")
      .set("Authorization", header)
      .send({
        title: "Admin-created report",
        description: "A report created by a regional administrator.",
        category: "ROADS",
        area: "Area",
        address: "Address",
      });

    expect(res.status).toBe(201);
    expect(res.body.userId).toBe(user.id);
    expect(res.body.state).toBe("Maharashtra");
    expect(res.body.district).toBe("Pune");
  });
});
