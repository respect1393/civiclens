import { randomUUID } from "node:crypto";
import bcrypt from "bcryptjs";
import { prisma } from "../../src/db";

const DEFAULT_PASSWORD = "password123";

export interface CreateUserInput {
  name?: string;
  email?: string;
  password?: string;
  role?: "CITIZEN" | "ADMIN";
  state?: string | null;
  district?: string | null;
}

export interface CreatedUser {
  user: Awaited<ReturnType<typeof prisma.user.create>>;
  password: string;
}

/**
 * Inserts a user directly (bypassing the HTTP layer) and returns the row plus
 * its plaintext password so login tests have known credentials.
 */
export async function createUser(input: CreateUserInput = {}): Promise<CreatedUser> {
  const password = input.password ?? DEFAULT_PASSWORD;
  const user = await prisma.user.create({
    data: {
      name: input.name ?? "Test User",
      email: input.email ?? `user-${randomUUID()}@example.com`,
      passwordHash: await bcrypt.hash(password, 10),
      role: input.role ?? "CITIZEN",
      state: input.state === undefined ? "Maharashtra" : input.state,
      district: input.district === undefined ? "Pune" : input.district,
    },
  });
  return { user, password };
}

export interface CreateReportInput {
  title?: string;
  description?: string;
  category?: "ROADS" | "STREETLIGHTS" | "WATER" | "WASTE" | "DRAINAGE" | "SAFETY";
  area?: string;
  address?: string;
  state?: string | null;
  district?: string | null;
}

/** Inserts a report owned by `userId` directly (bypassing the HTTP layer). */
export async function createReport(userId: string, input: CreateReportInput = {}) {
  return prisma.report.create({
    data: {
      title: input.title ?? "Test Report",
      description: input.description ?? "A report created for testing.",
      category: input.category ?? "ROADS",
      area: input.area ?? "Test Area",
      address: input.address ?? "1 Test Street",
      userId,
      state: input.state === undefined ? "Maharashtra" : input.state,
      district: input.district === undefined ? "Pune" : input.district,
    },
  });
}
