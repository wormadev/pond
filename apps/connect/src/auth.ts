import { z } from "zod";
import { randomToken, sameDigest, sha256 } from "./crypto";
import type { Env } from "./index";

/**
 * The password never reaches this service. Clients stretch it with PBKDF2 and send the result as `key`;
 * only a salted hash of that key is stored, so a leaked database holds nothing that signs in.
 */
const credentials = z.object({
  email: z.string().trim().toLowerCase().email().max(254),
  key: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
  device: z.object({
    kind: z.enum(["mac", "phone"]),
    name: z.string().trim().min(1).max(80),
  }),
});

export interface Session {
  userId: string;
  kind: "mac" | "phone";
}

export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

const wrongCredentials = () =>
  new HttpError(
    401,
    "wrong_credentials",
    "That email and password don't match an account.",
  );

async function limit(env: Env, request: Request, email: string): Promise<void> {
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  const byIp = await env.AUTH_LIMIT.limit({ key: `ip:${ip}` });
  const byEmail = await env.AUTH_LIMIT.limit({ key: `email:${email}` });
  if (!byIp.success || !byEmail.success) {
    throw new HttpError(
      429,
      "slow_down",
      "Too many attempts. Wait a minute and try again.",
    );
  }
}

async function openSession(
  env: Env,
  userId: string,
  device: z.infer<typeof credentials>["device"],
): Promise<string> {
  const token = randomToken();
  const now = Date.now();
  await env.DB.prepare(
    "INSERT INTO sessions (token_hash, user_id, kind, name, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?)",
  )
    .bind(await sha256(token), userId, device.kind, device.name, now, now)
    .run();
  return token;
}

export async function signUp(
  env: Env,
  request: Request,
): Promise<{ token: string }> {
  const input = credentials.parse(await request.json());
  await limit(env, request, input.email);
  const id = crypto.randomUUID();
  const salt = randomToken(16);
  const created = await env.DB.prepare(
    "INSERT INTO users (id, email, salt, key_hash, created_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT (email) DO NOTHING",
  )
    .bind(id, input.email, salt, await sha256(salt + input.key), Date.now())
    .run();
  if (created.meta.changes === 0) {
    throw new HttpError(
      409,
      "email_taken",
      "An account with that email already exists. Sign in instead.",
    );
  }
  return { token: await openSession(env, id, input.device) };
}

export async function signIn(
  env: Env,
  request: Request,
): Promise<{ token: string }> {
  const input = credentials.parse(await request.json());
  await limit(env, request, input.email);
  const user = await env.DB.prepare(
    "SELECT id, salt, key_hash FROM users WHERE email = ?",
  )
    .bind(input.email)
    .first<{ id: string; salt: string; key_hash: string }>();
  // Hash even when the account is missing, so both failures take the same time.
  const digest = await sha256((user?.salt ?? "missing") + input.key);
  if (!user || !sameDigest(digest, user.key_hash)) throw wrongCredentials();
  return { token: await openSession(env, user.id, input.device) };
}

const tokenProtocolPrefix = "bearer.";

export function bearer(request: Request): string | null {
  const header = request.headers.get("authorization") ?? "";
  if (header.toLowerCase().startsWith("bearer ")) return header.slice(7).trim();
  // Desktop WebSocket clients can't set headers, so the Mac's socket carries its token as a subprotocol.
  const offered = (request.headers.get("sec-websocket-protocol") ?? "")
    .split(",")
    .map((entry) => entry.trim());
  return (
    offered
      .find((entry) => entry.startsWith(tokenProtocolPrefix))
      ?.slice(tokenProtocolPrefix.length) ?? null
  );
}

export async function requireSession(
  env: Env,
  request: Request,
): Promise<Session & { tokenHash: string }> {
  const token = bearer(request);
  if (!token) throw new HttpError(401, "unauthorized", "Sign in to continue.");
  const tokenHash = await sha256(token);
  const row = await env.DB.prepare(
    "SELECT user_id, kind FROM sessions WHERE token_hash = ?",
  )
    .bind(tokenHash)
    .first<{ user_id: string; kind: "mac" | "phone" }>();
  if (!row) throw new HttpError(401, "unauthorized", "Sign in to continue.");
  return { userId: row.user_id, kind: row.kind, tokenHash };
}

export async function signOut(env: Env, tokenHash: string): Promise<void> {
  await env.DB.prepare("DELETE FROM sessions WHERE token_hash = ?")
    .bind(tokenHash)
    .run();
}
