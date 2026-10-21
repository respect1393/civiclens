import jwt from "jsonwebtoken";

const JWT_SECRET = process.env.JWT_SECRET;

if (!JWT_SECRET) {
  throw new Error("JWT_SECRET must be set before importing the token helper");
}

export interface TokenPayload {
  id: string;
  email: string;
  role: string;
}

/** Signs a valid token with the test JWT secret. */
export function signToken(
  payload: TokenPayload,
  options: jwt.SignOptions = {}
): string {
  return jwt.sign(payload, JWT_SECRET as string, { expiresIn: "7d", ...options });
}

/** Signs a token with an arbitrary secret (used for tampering/wrong-secret tests). */
export function signWithSecret(
  payload: object,
  secret: string,
  options: jwt.SignOptions = {}
): string {
  return jwt.sign(payload, secret, options);
}

/** Verifies a token against the test JWT secret; throws when invalid. */
export function verifyToken(token: string): jwt.JwtPayload {
  return jwt.verify(token, JWT_SECRET as string) as jwt.JwtPayload;
}

/** Builds an Authorization header value. */
export function bearer(token: string): string {
  return `Bearer ${token}`;
}
