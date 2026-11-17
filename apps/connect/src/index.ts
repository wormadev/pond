import { z } from "zod";
import { HttpError, requireSession, signIn, signOut, signUp } from "./auth";
import { failure } from "./relay";

export { Relay } from "./relay";

export interface Env {
  DB: D1Database;
  RELAY: DurableObjectNamespace<import("./relay").Relay>;
  AUTH_LIMIT: RateLimit;
  RELAY_LIMIT: RateLimit;
}

const machineInput = z.object({ name: z.string().trim().min(1).max(80) });
const ok = (data: unknown) => Response.json({ status: "success", data });

async function ownedMachine(
  env: Env,
  userId: string,
  id: string,
): Promise<void> {
  const row = await env.DB.prepare(
    "SELECT 1 FROM machines WHERE id = ? AND user_id = ?",
  )
    .bind(id, userId)
    .first();
  if (!row)
    throw new HttpError(
      404,
      "not_found",
      "That Mac isn't linked to your account.",
    );
}

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname;
  const method = request.method;

  if (method === "POST" && path === "/v1/signup")
    return ok(await signUp(env, request));
  if (method === "POST" && path === "/v1/login")
    return ok(await signIn(env, request));
  if (method === "GET" && path === "/") return new Response("Pond Connect\n");

  const session = await requireSession(env, request);
  const limited = await env.RELAY_LIMIT.limit({ key: session.userId });
  if (!limited.success)
    throw new HttpError(
      429,
      "slow_down",
      "Too many requests. Try again in a minute.",
    );

  if (method === "POST" && path === "/v1/logout") {
    await signOut(env, session.tokenHash);
    return ok({});
  }

  if (method === "GET" && path === "/v1/me") {
    const user = await env.DB.prepare("SELECT email FROM users WHERE id = ?")
      .bind(session.userId)
      .first<{ email: string }>();
    const machines = await env.DB.prepare(
      "SELECT id, name FROM machines WHERE user_id = ? ORDER BY created_at",
    )
      .bind(session.userId)
      .all<{ id: string; name: string }>();
    const withStatus = await Promise.all(
      machines.results.map(async (machine) => ({
        ...machine,
        online: await env.RELAY.getByName(machine.id).isOnline(),
      })),
    );
    return ok({ email: user?.email, machines: withStatus });
  }

  if (method === "POST" && path === "/v1/machines") {
    if (session.kind !== "mac")
      throw new HttpError(403, "forbidden", "Only a Mac can link itself.");
    const input = machineInput.parse(await request.json());
    const id = crypto.randomUUID();
    await env.DB.prepare(
      "INSERT INTO machines (id, user_id, name, created_at) VALUES (?, ?, ?, ?)",
    )
      .bind(id, session.userId, input.name, Date.now())
      .run();
    return ok({ id });
  }

  const machine = path.match(/^\/v1\/machines\/([0-9a-f-]{36})(\/connect)?$/);
  if (machine) {
    const id = machine[1] as string;
    await ownedMachine(env, session.userId, id);
    if (method === "DELETE" && !machine[2]) {
      await env.DB.prepare("DELETE FROM machines WHERE id = ? AND user_id = ?")
        .bind(id, session.userId)
        .run();
      return ok({});
    }
    if (method === "GET" && machine[2]) {
      if (
        session.kind !== "mac" ||
        request.headers.get("upgrade") !== "websocket"
      ) {
        throw new HttpError(
          426,
          "upgrade_required",
          "Connect with a WebSocket from the Mac.",
        );
      }
      return env.RELAY.getByName(id).fetch(request);
    }
  }

  const proxied = path.match(/^\/m\/([0-9a-f-]{36})(\/api\/v2\/.*)$/);
  if (proxied) {
    const id = proxied[1] as string;
    await ownedMachine(env, session.userId, id);
    const headers = new Headers(request.headers);
    headers.delete("authorization");
    headers.set("x-relay-path", (proxied[2] as string) + url.search);
    return env.RELAY.getByName(id).fetch(
      new Request(request.url, { method, headers, body: request.body }),
    );
  }

  throw new HttpError(404, "not_found", "Nothing here.");
}

export default {
  async fetch(request, env): Promise<Response> {
    try {
      return await route(request, env);
    } catch (error) {
      if (error instanceof HttpError)
        return failure(error.status, error.code, error.message);
      if (error instanceof z.ZodError || error instanceof SyntaxError) {
        return failure(400, "invalid", "That request isn't valid.");
      }
      console.error(
        JSON.stringify({ message: "unhandled", error: String(error) }),
      );
      return failure(500, "internal", "Something went wrong.");
    }
  },
} satisfies ExportedHandler<Env>;
