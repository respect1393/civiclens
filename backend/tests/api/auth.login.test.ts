import { describe, expect, it } from "vitest";
import request from "supertest";
import { createApp } from "../../src/app";
import { createUser } from "../helpers/factory";
import { verifyToken } from "../helpers/token";

const app = createApp();

describe("POST /api/auth/login", () => {
  it("logs in with correct credentials and returns a token", async () => {
    const { user, password } = await createUser({
      name: "Login Tester",
      email: "login.tester@example.com",
      password: "correcthorsebattery",
      role: "CITIZEN",
      state: "Maharashtra",
      district: "Pune",
    });

    const res = await request(app)
      .post("/api/auth/login")
      .send({ email: user.email, password });

    expect(res.status).toBe(200);
    expect(res.body.user).toMatchObject({
      id: user.id,
      name: "Login Tester",
      email: user.email,
      state: "Maharashtra",
      district: "Pune",
      role: "CITIZEN",
    });
    expect(res.body.user).not.toHaveProperty("passwordHash");

    const payload = verifyToken(res.body.token);
    expect(payload).toMatchObject({ id: user.id, email: user.email, role: "CITIZEN" });
  });

  it("logs in an administrator and reports the ADMIN role", async () => {
    const { user, password } = await createUser({
      email: "admin.login@example.com",
      password: "adminpassword123",
      role: "ADMIN",
      state: null,
      district: null,
    });

    const res = await request(app)
      .post("/api/auth/login")
      .send({ email: user.email, password });

    expect(res.status).toBe(200);
    expect(res.body.user.role).toBe("ADMIN");
    expect(res.body.user).not.toHaveProperty("passwordHash");
  });

  it("rejects a wrong password with the generic 401 message", async () => {
    const { user } = await createUser({ email: "wrong.pw@example.com" });

    const res = await request(app)
      .post("/api/auth/login")
      .send({ email: user.email, password: "definitely-wrong" });

    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "Invalid credentials" });
  });

  it("rejects an unknown email with the same generic 401 message", async () => {
    const res = await request(app)
      .post("/api/auth/login")
      .send({ email: "nobody@example.com", password: "whatever123" });

    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "Invalid credentials" });
  });

  it.each([
    ["invalid email", { email: "not-an-email", password: "password123" }],
    ["missing password", { email: "someone@example.com" }],
    ["empty password", { email: "someone@example.com", password: "" }],
    ["empty body", {}],
  ])("rejects invalid payload (%s) with 400", async (_label, payload) => {
    const res = await request(app).post("/api/auth/login").send(payload);

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Invalid login data");
    expect(res.body.details).toBeDefined();
  });
});
