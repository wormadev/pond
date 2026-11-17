import { pbkdf2 } from "node:crypto";
import { hostname } from "node:os";
import { promisify } from "node:util";
import { API_TOKEN_SCOPES } from "@pond/schema/api";
import log from "electron-log/main.js";
import { z } from "zod";
import {
  CONNECT_SERVER,
  KEYCHAIN_CONNECT_SESSION,
} from "../../shared/constants";
import type {
  ConnectDevice,
  ConnectStatus,
} from "../../shared/query-contracts-system";
import { USER_ERROR_NAME, userError } from "../../shared/user-error";
import { apiTokens } from "../http/api-tokens";
import { deleteSecret, getSecret, setSecret } from "../keychain";
import { openRelay } from "./relay";

const derive = promisify(pbkdf2);

const SessionSchema = z.object({
  email: z.string(),
  machineId: z.uuid(),
  token: z.string().min(1),
  apiToken: z.string().min(1),
  apiTokenId: z.string().min(1),
});
type Session = z.infer<typeof SessionSchema>;

const ReplySchema = z.object({
  data: z.unknown().optional(),
  error: z.object({ message: z.string() }).optional(),
});
const TokenSchema = z.object({ token: z.string().min(1) });
const MachinesSchema = z.object({
  machines: z.array(z.object({ id: z.uuid(), name: z.string() })),
});
const MachineSchema = z.object({ id: z.uuid() });
const DevicesSchema = z.object({
  devices: z.array(
    z.object({
      kind: z.enum(["mac", "phone"]),
      name: z.string(),
      signedInAt: z.number(),
      lastSeenAt: z.number(),
      current: z.boolean(),
    }),
  ),
});

/** Carries the service's own sentence to the screen, plus the status the caller branches on. */
class ConnectError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
    this.name = USER_ERROR_NAME;
  }
}

let relay: ReturnType<typeof openRelay> | null = null;

/** The password stays on this Mac: the service only ever receives this stretched key. */
async function deriveKey(email: string, password: string): Promise<string> {
  const key = await derive(
    password,
    `pond-connect:${email}`,
    600_000,
    32,
    "sha256",
  );
  return key.toString("base64url");
}

async function call<Schema extends z.ZodType>(
  schema: Schema,
  path: string,
  init: { method?: string; token?: string; body?: unknown } = {},
): Promise<z.infer<Schema>> {
  let response: Response;
  try {
    response = await fetch(CONNECT_SERVER + path, {
      method: init.method ?? "GET",
      headers: {
        "content-type": "application/json",
        ...(init.token && { authorization: `Bearer ${init.token}` }),
      },
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
    });
  } catch {
    throw userError("Couldn't reach Pond Connect. Check your connection.");
  }
  const reply = ReplySchema.safeParse(await response.json().catch(() => null));
  if (!response.ok || !reply.success) {
    throw new ConnectError(
      (reply.success && reply.data.error?.message) ||
        "Pond Connect couldn't finish that. Try again.",
      response.status,
    );
  }
  return schema.parse(reply.data.data);
}

async function readSession(): Promise<Session | null> {
  const raw = await getSecret(KEYCHAIN_CONNECT_SESSION);
  if (!raw) return null;
  const parsed = SessionSchema.safeParse(JSON.parse(raw));
  return parsed.success ? parsed.data : null;
}

/** The relay reaches Pond with its own scoped token, so a phone never gets the routes reserved for the Local API Token. */
async function withApiToken(session: Session): Promise<Session> {
  const current = (await apiTokens.list()).find(
    (token) => token.id === session.apiTokenId,
  );
  if (current && API_TOKEN_SCOPES.every((s) => current.scopes.includes(s)))
    return session;
  /** A token from before a scope was added is replaced, so the phone gains it without signing in again. */
  if (current) await apiTokens.revoke(current.id);
  const created = await apiTokens.create("Pond Connect", API_TOKEN_SCOPES);
  const next = {
    ...session,
    apiToken: created.token,
    apiTokenId: created.info.id,
  };
  await setSecret(KEYCHAIN_CONNECT_SESSION, JSON.stringify(next));
  return next;
}

async function forget(session: Session): Promise<void> {
  relay?.close();
  relay = null;
  await apiTokens.revoke(session.apiTokenId);
  await deleteSecret(KEYCHAIN_CONNECT_SESSION);
}

function start(session: Session): void {
  relay?.close();
  relay = openRelay({
    machineId: session.machineId,
    token: session.token,
    apiToken: session.apiToken,
    onRejected: () => {
      void call(MachinesSchema, "/v1/me", { token: session.token }).catch(
        async (cause) => {
          if (cause instanceof ConnectError && cause.status === 401) {
            log.warn("[pond connect] session ended on the server");
            await forget(session);
          }
        },
      );
    },
  });
}

export async function connectStatus(): Promise<ConnectStatus> {
  const session = await readSession();
  return { email: session?.email ?? null, online: relay?.isOpen() ?? false };
}

export async function connectDevices(): Promise<{ devices: ConnectDevice[] }> {
  const session = await readSession();
  if (!session) return { devices: [] };
  return call(DevicesSchema, "/v1/me", { token: session.token });
}

export async function startConnect(): Promise<void> {
  const session = await readSession();
  if (session) start(await withApiToken(session));
}

export function stopConnect(): void {
  relay?.close();
  relay = null;
}

export async function connectSignIn(input: {
  email: string;
  password: string;
  creating: boolean;
}): Promise<ConnectStatus> {
  const existing = await readSession();
  if (existing) await connectSignOut();
  const email = input.email.trim().toLowerCase();
  const name = hostname();
  const { token } = await call(
    TokenSchema,
    input.creating ? "/v1/signup" : "/v1/login",
    {
      method: "POST",
      body: {
        email,
        key: await deriveKey(email, input.password),
        device: { kind: "mac", name },
      },
    },
  );
  const { machines } = await call(MachinesSchema, "/v1/me", { token });
  const machine =
    machines.find((entry) => entry.name === name) ??
    (await call(MachineSchema, "/v1/machines", {
      method: "POST",
      token,
      body: { name },
    }));
  const created = await apiTokens.create("Pond Connect", API_TOKEN_SCOPES);
  const session: Session = {
    email,
    machineId: machine.id,
    token,
    apiToken: created.token,
    apiTokenId: created.info.id,
  };
  await setSecret(KEYCHAIN_CONNECT_SESSION, JSON.stringify(session));
  start(session);
  return { email, online: false };
}

export async function connectSignOut(): Promise<ConnectStatus> {
  const session = await readSession();
  if (!session) return { email: null, online: false };
  await forget(session);
  /** Signing out must work offline; the server copy is cleaned up when it can be reached. */
  try {
    await call(z.unknown(), `/v1/machines/${session.machineId}`, {
      method: "DELETE",
      token: session.token,
    });
    await call(z.unknown(), "/v1/logout", {
      method: "POST",
      token: session.token,
    });
  } catch (cause) {
    log.warn("[pond connect] couldn't end the session on the server", cause);
  }
  return { email: null, online: false };
}
