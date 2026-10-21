/**
 * Local, provider-independent storage for report images.
 *
 * The module deliberately knows nothing about Express or Prisma: it validates
 * image bytes, turns them into a content-addressed key under a single root
 * directory and hands back safe absolute paths. Because it deals only in files
 * and opaque keys, the same interface could later be backed by an object store
 * without touching the routes.
 */

import { createHash } from "node:crypto";
import { promises as fs } from "node:fs";
import path from "node:path";

/** Sub-directory (inside the upload root) that holds report images. */
export const REPORT_IMAGE_PREFIX = "reports";

/** Image formats the backend accepts, identified from the bytes themselves. */
export type ImageFormat = "jpeg" | "png" | "webp";

const EXTENSION_BY_FORMAT: Record<ImageFormat, string> = {
  jpeg: "jpg",
  png: "png",
  webp: "webp",
};

const MIME_BY_EXTENSION: Record<string, string> = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
};

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/**
 * Detects a supported image format from the leading bytes of [buffer].
 *
 * The signature is the source of truth: a client-declared content type is
 * never trusted. Returns null for anything that is not a JPEG, PNG or WebP.
 */
export function detectImageFormat(buffer: Buffer): ImageFormat | null {
  if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return "jpeg";
  }

  if (buffer.length >= 8 && buffer.subarray(0, 8).equals(PNG_SIGNATURE)) {
    return "png";
  }

  if (
    buffer.length >= 12 &&
    buffer.subarray(0, 4).toString("ascii") === "RIFF" &&
    buffer.subarray(8, 12).toString("ascii") === "WEBP"
  ) {
    return "webp";
  }

  return null;
}

/** The canonical file extension for a detected format. */
export function extensionFor(format: ImageFormat): string {
  return EXTENSION_BY_FORMAT[format];
}

/** The MIME type for a stored key's extension, or null when unknown. */
export function mimeTypeForKey(key: string): string | null {
  const extension = path.extname(key).replace(/^\./, "").toLowerCase();
  return MIME_BY_EXTENSION[extension] ?? null;
}

/**
 * A stable, server-controlled, content-addressed storage key.
 *
 * The key is built entirely from a hash of the bytes and the detected format,
 * so it can never contain user input, a path separator or a traversal
 * sequence. Identical images map to the same file, which also makes the
 * "shared by more than one report" case meaningful on deletion.
 */
export function reportImageKey(buffer: Buffer, format: ImageFormat): string {
  const digest = createHash("sha256").update(buffer).digest("hex");
  return `${REPORT_IMAGE_PREFIX}/${digest}.${extensionFor(format)}`;
}

/** Creates [dir] (and parents) when missing. */
export async function ensureDir(dir: string): Promise<void> {
  await fs.mkdir(dir, { recursive: true });
}

/**
 * Resolves [key] inside [root], or returns null when the result would escape
 * the root. This is the defence against path traversal and arbitrary file
 * access for any path that ends up derived from stored data.
 */
export function resolveWithin(root: string, key: string): string | null {
  const normalisedRoot = path.resolve(root);
  const resolved = path.resolve(normalisedRoot, key);
  if (resolved !== normalisedRoot && !resolved.startsWith(normalisedRoot + path.sep)) {
    return null;
  }
  return resolved;
}

/**
 * Writes [buffer] to [absolutePath] atomically (temp file + rename).
 *
 * Content-addressed files are immutable, so an existing file is left as-is.
 */
export async function writeImageAtomic(absolutePath: string, buffer: Buffer): Promise<void> {
  await ensureDir(path.dirname(absolutePath));

  try {
    await fs.access(absolutePath);
    return;
  } catch {
    // Not stored yet — fall through and write it.
  }

  const temporary = `${absolutePath}.${process.pid}.${Date.now()}.tmp`;
  try {
    await fs.writeFile(temporary, buffer);
    await fs.rename(temporary, absolutePath);
  } catch (error) {
    await fs.rm(temporary, { force: true }).catch(() => undefined);
    throw error;
  }
}

/** Removes a stored image, treating "already gone" as success. */
export async function deleteImageIfExists(absolutePath: string): Promise<void> {
  try {
    await fs.unlink(absolutePath);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") {
      throw error;
    }
  }
}

/** Whether a stored image exists on disk. */
export async function imageExists(absolutePath: string): Promise<boolean> {
  try {
    const stats = await fs.stat(absolutePath);
    return stats.isFile();
  } catch {
    return false;
  }
}
