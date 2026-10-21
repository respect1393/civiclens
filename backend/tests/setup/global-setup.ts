import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT_ROOT = join(__dirname, "..", "..");

/**
 * Creates a brand-new, disposable SQLite database inside the OS temp directory
 * and applies the Prisma migrations to it.
 *
 * The resulting path is exported through process.env.DATABASE_URL and inherited
 * by every test worker. Nothing here ever reads or writes dev.db,
 * dev.db.backup or dev.db.test.
 */
export default function globalSetup() {
  const dir = mkdtempSync(join(tmpdir(), "civiclens-test-"));
  const dbFile = join(dir, "test.db");

  // Must be set before src/db.ts is imported by any worker.
  process.env.DATABASE_URL = `file:${dbFile}`;
  process.env.JWT_SECRET =
    process.env.CIVICLENS_TEST_JWT_SECRET ??
    "civiclens-test-only-secret-0123456789abcdef";

  execFileSync("npx", ["--no-install", "prisma", "migrate", "deploy"], {
    cwd: PROJECT_ROOT,
    env: process.env,
    stdio: "ignore",
  });

  return () => {
    rmSync(dir, { recursive: true, force: true });
  };
}
