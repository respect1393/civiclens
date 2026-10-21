import { tmpdir } from "node:os";
import { basename, resolve } from "node:path";

/**
 * Databases that must NEVER be opened by the test suite.
 */
const PROTECTED_FILES = new Set(["dev.db", "dev.db.backup", "dev.db.test"]);

/**
 * Validates a test DATABASE_URL and returns the resolved absolute file path.
 *
 * Throws unless the URL points at a `file:` inside the OS temp directory and is
 * not one of the protected development databases. This is the last line of
 * defence: if anything is misconfigured the suite fails instead of touching a
 * real database.
 */
export function assertSafeTestDb(url: string | undefined): string {
  if (!url) {
    throw new Error(
      "Refusing to run tests: DATABASE_URL is not set. Tests require an isolated temp database."
    );
  }

  if (!url.startsWith("file:")) {
    throw new Error(
      `Refusing to run tests: DATABASE_URL must be a file: URL, received "${url}".`
    );
  }

  const absolute = resolve(url.slice("file:".length));
  const name = basename(absolute);

  if (PROTECTED_FILES.has(name)) {
    throw new Error(
      `Refusing to run tests against protected database "${name}". ` +
        "Tests must never touch dev.db, dev.db.backup or dev.db.test."
    );
  }

  if (!absolute.startsWith(resolve(tmpdir()))) {
    throw new Error(
      `Refusing to run tests: database "${absolute}" is not inside the OS temp directory. ` +
        "Tests only run against a disposable temp database."
    );
  }

  return absolute;
}
