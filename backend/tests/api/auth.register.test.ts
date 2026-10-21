import { describe, expect, it } from "vitest";
import request from "supertest";
import { createApp } from "../../src/app";
import { prisma } from "../../src/db";
import { verifyToken } from "../helpers/token";

const app = createApp();

const validRegistration = {
  name: "Asha Rao",
  email: "asha.rao@example.com",
  password: "supersecret123",
  state: "Maharashtra",
  district: "Pune",
};

describe("POST /api/auth/register", () => {
  it("registers a new citizen and returns a token", async () => {
    const res = await request(app).post("/api/auth/register").send(validRegistration);

    expect(res.status).toBe(201);
    expect(res.body.user).toMatchObject({
      name: validRegistration.name,
      email: validRegistration.email,
      state: validRegistration.state,
      district: validRegistration.district,
      role: "CITIZEN",
    });
    expect(res.body.user.id).toBeTruthy();
    expect(res.body.user).not.toHaveProperty("passwordHash");

    const payload = verifyToken(res.body.token);
    expect(payload).toMatchObject({
      id: res.body.user.id,
      email: validRegistration.email,
      role: "CITIZEN",
    });
  });

  it("stores a bcrypt hash rather than the plaintext password", async () => {
    await request(app).post("/api/auth/register").send(validRegistration);

    const stored = await prisma.user.findUnique({
      where: { email: validRegistration.email },
    });

    expect(stored?.passwordHash).toBeTruthy();
    expect(stored?.passwordHash).not.toBe(validRegistration.password);
    expect(stored?.passwordHash).toMatch(/^\$2[aby]\$/);
  });

  it("always assigns the CITIZEN role, even if ADMIN is requested", async () => {
    const res = await request(app)
      .post("/api/auth/register")
      .send({ ...validRegistration, role: "ADMIN" });

    expect(res.status).toBe(201);
    expect(res.body.user.role).toBe("CITIZEN");

    const stored = await prisma.user.findUnique({
      where: { email: validRegistration.email },
    });
    expect(stored?.role).toBe("CITIZEN");
  });

  it("rejects a duplicate email with 400", async () => {
    await request(app).post("/api/auth/register").send(validRegistration);

    const res = await request(app).post("/api/auth/register").send(validRegistration);

    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: "Email already registered" });
  });

  it.each([
    ["missing name", { ...validRegistration, name: undefined }],
    ["empty name", { ...validRegistration, name: "" }],
    ["invalid email", { ...validRegistration, email: "not-an-email" }],
    ["short password", { ...validRegistration, password: "short" }],
    ["missing state", { ...validRegistration, state: undefined }],
    ["empty state", { ...validRegistration, state: "" }],
    ["missing district", { ...validRegistration, district: undefined }],
  ])("rejects invalid payload (%s) with 400", async (_label, payload) => {
    const res = await request(app).post("/api/auth/register").send(payload);

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Invalid registration data");
    expect(res.body.details).toBeDefined();
  });

  it("rejects an empty body with 400", async () => {
    const res = await request(app).post("/api/auth/register").send({});

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Invalid registration data");
  });
});
