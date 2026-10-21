/**
 * Centralised environment configuration validation.
 *
 * Values are validated lazily (when read) so importing this module has no side
 * effects. Secret values are never logged or included in error messages.
 */

import path from "node:path";

const MIN_JWT_SECRET_LENGTH = 32;

/**
 * Maximum accepted upload size for a report image, in bytes (5 MB).
 *
 * Declared here so the route-level raw body parser and the documentation share
 * one number.
 */
export const MAX_IMAGE_BYTES = 5 * 1024 * 1024;

/**
 * Returns the configured JWT secret, enforcing the minimum length policy.
 * Throws a clear error when it is missing or too short.
 */
export function getJwtSecret(): string {
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    throw new Error("JWT_SECRET is not defined in the environment");
  }
  if (secret.length < MIN_JWT_SECRET_LENGTH) {
    throw new Error("JWT_SECRET must be at least 32 characters long");
  }
  return secret;
}

/**
 * Returns the configured database URL. There is deliberately no fallback: a
 * missing DATABASE_URL must fail loudly rather than silently using dev.db.
 */
export function getDatabaseUrl(): string {
  const url = process.env.DATABASE_URL;
  if (!url) {
    throw new Error("DATABASE_URL is not defined in the environment");
  }
  return url;
}

/**
 * Directory where uploaded report images are stored.
 *
 * `UPLOAD_DIR` may be absolute or relative to the current working directory
 * (the documented working directory is `backend/`). When it is not set the
 * default is `<backend>/uploads`, resolved from this module's location so the
 * path is identical whether the server runs from `src` (tsx) or `dist` (node)
 * and regardless of the shell's working directory.
 */
export function getUploadDir(): string {
  const configured = process.env.UPLOAD_DIR?.trim();
  if (configured) {
    return path.isAbsolute(configured)
      ? configured
      : path.resolve(process.cwd(), configured);
  }
  return path.resolve(__dirname, "..", "uploads");
}
