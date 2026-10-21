import "dotenv/config";
import { PrismaBetterSqlite3 } from "@prisma/adapter-better-sqlite3";
import { PrismaClient } from "./generated/prisma/client";
import { getDatabaseUrl } from "./config";

// No fallback: DATABASE_URL must be configured explicitly (e.g. via .env),
// otherwise startup fails clearly instead of silently using dev.db.
const adapter = new PrismaBetterSqlite3({
  url: getDatabaseUrl(),
});

export const prisma = new PrismaClient({ adapter });
