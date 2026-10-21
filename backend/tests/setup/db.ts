import { afterAll, beforeEach } from "vitest";
import { assertSafeTestDb } from "../helpers/safety";

// Guard BEFORE importing src/db, because src/db builds its Prisma client from
// process.env.DATABASE_URL at import time (there is no fallback database).
assertSafeTestDb(process.env.DATABASE_URL);

const { prisma } = await import("../../src/db");

/**
 * Removes all rows from the shared temp database. Children are deleted before
 * their parents to satisfy foreign keys.
 */
async function resetDatabase() {
  await prisma.adminNote.deleteMany();
  await prisma.statusHistory.deleteMany();
  await prisma.report.deleteMany();
  await prisma.user.deleteMany();
}

beforeEach(async () => {
  await resetDatabase();
});

afterAll(async () => {
  await prisma.$disconnect();
});
