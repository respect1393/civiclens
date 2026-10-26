import { describe, expect, it } from "vitest";
import request from "supertest";
import { createApp } from "../../src/app";
import { createUser } from "../helpers/factory";
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

describe("GET /api/admins", () => {
  it("requires authentication", async () => {
    const res = await request(app).get("/api/admins");
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "Unauthorized" });
  });

  it("forbids a citizen from listing administrators", async () => {
    const { header } = await createCitizen();

    const res = await request(app).get("/api/admins").set("Authorization", header);

    expect(res.status).toBe(403);
    expect(res.body).toEqual({
      error: "Forbidden: insufficient permissions",
    });
  });

  it("lists existing administrator accounts", async () => {
    const { header } = await createAdmin();
    await createUser({ email: "a@example.com", role: "ADMIN", state: null, district: null });
    await createUser({ email: "b@example.com", role: "ADMIN", state: null, district: null });
    await createUser({ email: "c@example.com", role: "CITIZEN", state: null, district: null });

    const res = await request(app).get("/api/admins").set("Authorization", header);

    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(3);
    for (const admin of res.body.data) {
      expect(admin.role).toBe("ADMIN");
      expect(admin).not.toHaveProperty("passwordHash");
    }
  });
});

describe("POST /api/admins", () => {
  const validAdmin = {
    name: "Asha Rao",
    email: "asha.rao@example.com",
    password: "supersecret123",
    state: "Maharashtra",
    district: "Pune",
  };

  it("requires authentication", async () => {
    const res = await request(app).post("/api/admins").send(validAdmin);
    expect(res.status).toBe(401);
  });

  it("forbids a citizen from creating an administrator", async () => {
    const { header } = await createCitizen();

    const res = await request(app)
      .post("/api/admins")
      .set("Authorization", header)
      .send(validAdmin);

    expect(res.status).toBe(403);
    expect(res.body).toEqual({
      error: "Forbidden: insufficient permissions",
    });
  });

  it("rejects an invalid payload", async () => {
    const { header } = await createAdmin();

    const res = await request(app)
      .post("/api/admins")
      .set("Authorization", header)
      .send({ ...validAdmin, password: "short" });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Invalid administrator data");
  });

  it("requires state", async () => {
    const { header } = await createAdmin();

    const res = await request(app)
      .post("/api/admins")
      .set("Authorization", header)
      .send({ ...validAdmin, state: "" });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Invalid administrator data");
  });

  it("rejects a duplicate email with 409", async () => {
    const { header } = await createAdmin();

    await createUser({ email: validAdmin.email, role: "ADMIN", state: null, district: null });

    const res = await request(app)
      .post("/api/admins")
      .set("Authorization", header)
      .send(validAdmin);

    expect(res.status).toBe(409);
    expect(res.body).toEqual({ error: "Email already registered" });
  });

  it("normalizes email and rejects duplicates case-insensitively", async () => {
    const { header } = await createAdmin();

    // Create via the API so the stored email is normalized to lowercase.
    await request(app)
      .post("/api/admins")
      .set("Authorization", header)
      .send(validAdmin);

    // Same address, different casing: should be rejected as a duplicate.
    const res = await request(app)
      .post("/api/admins")
      .set("Authorization", header)
      .send({ ...validAdmin, email: validAdmin.email.toUpperCase() });

    expect(res.status).toBe(409);
    expect(res.body).toEqual({ error: "Email already registered" });
  });

  it("creates an administrator with ADMIN role and safe fields", async () => {
    const { header } = await createAdmin();

    const res = await request(app)
      .post("/api/admins")
      .set("Authorization", header)
      .send(validAdmin);

    expect(res.status).toBe(201);
    expect(res.body).toMatchObject({
      name: validAdmin.name,
      email: validAdmin.email.toLowerCase(),
      role: "ADMIN",
      state: validAdmin.state,
      district: validAdmin.district,
    });
    expect(res.body.id).toBeTruthy();
    expect(res.body).not.toHaveProperty("passwordHash");
    expect(res.body).not.toHaveProperty("token");
  });

  it("never accepts a role from the client", async () => {
    const { header } = await createAdmin();
    const input = { ...validAdmin, email: "no-role@example.com", role: "CITIZEN" };

    const res = await request(app)
      .post("/api/admins")
      .set("Authorization", header)
      .send(input);

    expect(res.status).toBe(201);
    expect(res.body.role).toBe("ADMIN");

    const { prisma } = await import("../../src/db");
    const stored = await prisma.user.findUnique({
      where: { email: "no-role@example.com" },
    });
    expect(stored?.role).toBe("ADMIN");
  });

  it("stores a bcrypt hash rather than the plaintext password", async () => {
    const { header } = await createAdmin();
    const plaintext = "Plaintext123";

    await request(app)
      .post("/api/admins")
      .set("Authorization", header)
      .send({ ...validAdmin, email: "hashed@example.com", password: plaintext });

    const { prisma } = await import("../../src/db");
    const stored = await prisma.user.findUnique({
      where: { email: "hashed@example.com" },
    });

    expect(stored?.passwordHash).toBeTruthy();
    expect(stored?.passwordHash).not.toBe(plaintext);
    expect(stored?.passwordHash).toMatch(/^\$2[aby]\$/);
  });
});

describe("POST /api/invitations", () => {
  it("requires authentication", async () => {
    const res = await request(app)
      .post("/api/invitations")
      .send({ email: "invitee@example.com" });
    expect(res.status).toBe(401);
  });

  it("forbids a citizen from creating invitations", async () => {
    const { header } = await createCitizen();

    const res = await request(app)
      .post("/api/invitations")
      .set("Authorization", header)
      .send({ email: "invitee@example.com" });

    expect(res.status).toBe(403);
  });

  it("rejects an invalid email", async () => {
    const { header } = await createAdmin();

    const res = await request(app)
      .post("/api/invitations")
      .set("Authorization", header)
      .send({ email: "not-an-email" });

    expect(res.status).toBe(400);
  });

  it("creates a single-use invitation tied to an email", async () => {
    const { header } = await createAdmin();

    const res = await request(app)
      .post("/api/invitations")
      .set("Authorization", header)
      .send({ email: "invitee@example.com" });

    expect(res.status).toBe(201);
    expect(res.body.token).toBeTruthy();
    expect(res.body.email).toBe("invitee@example.com");
    expect(res.body.expiresAt).toBeTruthy();
    expect(res.body.usedAt).toBeFalsy();
  });

  it("revokes prior unused invitations for the same email", async () => {
    const { header } = await createAdmin();

    const first = await request(app)
      .post("/api/invitations")
      .set("Authorization", header)
      .send({ email: "invitee@example.com" });
    expect(first.status).toBe(201);

    const second = await request(app)
      .post("/api/invitations")
      .set("Authorization", header)
      .send({ email: "invitee@example.com" });
    expect(second.status).toBe(201);

    // The first invitation should now be marked as used.
    const { prisma } = await import("../../src/db");
    const invitations = await prisma.invitation.findMany({
      where: { email: "invitee@example.com" },
    });
    const unused = invitations.filter((i) => i.usedAt === null);
    expect(unused).toHaveLength(1);
    expect(unused[0].token).toBe(second.body.token);
  });
});

describe("POST /api/auth/register-admin", () => {
  const validRegistration = {
    name: "Asha Rao",
    email: "asha.rao@example.com",
    password: "supersecret123",
    confirmPassword: "supersecret123",
    state: "Maharashtra",
    district: "Pune",
  };

  it("requires an invitation token", async () => {
    const res = await request(app)
      .post("/api/auth/register-admin")
      .send({ ...validRegistration, invitationToken: "" });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Invalid registration data");
  });

  it("rejects an unknown invitation token", async () => {
    const res = await request(app)
      .post("/api/auth/register-admin")
      .send({ ...validRegistration, invitationToken: "nonexistent-token" });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Invalid invitation code");
  });

  it("rejects an already-used invitation token", async () => {
    const { header } = await createAdmin();
    const invite = await request(app)
      .post("/api/invitations")
      .set("Authorization", header)
      .send({ email: validRegistration.email });
    expect(invite.status).toBe(201);

    // Use the invitation once.
    await request(app)
      .post("/api/auth/register-admin")
      .send({ ...validRegistration, invitationToken: invite.body.token });

    // Try to use it again.
    const res = await request(app)
      .post("/api/auth/register-admin")
      .send({ ...validRegistration, email: "other@example.com", invitationToken: invite.body.token });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Invitation code has already been used");
  });

  it("rejects an expired invitation token", async () => {
    const { header } = await createAdmin();
    const { prisma } = await import("../../src/db");

    // Create an invitation directly with an expired date.
    const expired = await prisma.invitation.create({
      data: {
        token: "expired-token-12345",
        email: validRegistration.email,
        createdById: (await createUser({ email: "expired-admin@example.com", role: "ADMIN", state: null, district: null })).user.id,
        expiresAt: new Date(Date.now() - 1000),
      },
    });

    const res = await request(app)
      .post("/api/auth/register-admin")
      .send({ ...validRegistration, invitationToken: expired.token });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Invitation code has expired");
  });

  it("rejects when the invitation email does not match", async () => {
    const { header } = await createAdmin();
    const invite = await request(app)
      .post("/api/invitations")
      .set("Authorization", header)
      .send({ email: "invitee@example.com" });
    expect(invite.status).toBe(201);

    const res = await request(app)
      .post("/api/auth/register-admin")
      .send({ ...validRegistration, email: "different@example.com", invitationToken: invite.body.token });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Invitation code is not valid for this email address");
  });

  it("rejects when passwords do not match", async () => {
    const { header } = await createAdmin();
    const invite = await request(app)
      .post("/api/invitations")
      .set("Authorization", header)
      .send({ email: validRegistration.email });
    expect(invite.status).toBe(201);

    const res = await request(app)
      .post("/api/auth/register-admin")
      .send({ ...validRegistration, invitationToken: invite.body.token, confirmPassword: "different" });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Passwords do not match");
  });

  it("requires state", async () => {
    const { header } = await createAdmin();
    const invite = await request(app)
      .post("/api/invitations")
      .set("Authorization", header)
      .send({ email: validRegistration.email });
    expect(invite.status).toBe(201);

    const res = await request(app)
      .post("/api/auth/register-admin")
      .send({ ...validRegistration, invitationToken: invite.body.token, state: "" });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Invalid registration data");
  });

  it("rejects a duplicate email with 409", async () => {
    const { header } = await createAdmin();
    await createUser({ email: validRegistration.email, role: "ADMIN", state: null, district: null });

    const invite = await request(app)
      .post("/api/invitations")
      .set("Authorization", header)
      .send({ email: validRegistration.email });
    expect(invite.status).toBe(201);

    const res = await request(app)
      .post("/api/auth/register-admin")
      .send({ ...validRegistration, invitationToken: invite.body.token });

    expect(res.status).toBe(409);
    expect(res.body).toEqual({ error: "Email already registered" });
  });

  it("creates an administrator via invitation with ADMIN role and safe fields", async () => {
    const { header } = await createAdmin();
    const invite = await request(app)
      .post("/api/invitations")
      .set("Authorization", header)
      .send({ email: validRegistration.email });
    expect(invite.status).toBe(201);

    const res = await request(app)
      .post("/api/auth/register-admin")
      .send({ ...validRegistration, invitationToken: invite.body.token });

    expect(res.status).toBe(201);
    expect(res.body).toMatchObject({
      name: validRegistration.name,
      email: validRegistration.email.toLowerCase(),
      role: "ADMIN",
      state: validRegistration.state,
      district: validRegistration.district,
    });
    expect(res.body.id).toBeTruthy();
    expect(res.body).not.toHaveProperty("passwordHash");
    expect(res.body).not.toHaveProperty("token");

    // Invitation should be marked as used.
    const { prisma } = await import("../../src/db");
    const updated = await prisma.invitation.findUnique({
      where: { token: invite.body.token },
    });
    expect(updated?.usedAt).not.toBeNull();
    expect(updated?.usedById).toBe(res.body.id);
  });
});
