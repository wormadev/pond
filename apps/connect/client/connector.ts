import { execFileSync } from "node:child_process";
import { pbkdf2Sync } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir, hostname } from "node:os";
import { join } from "node:path";
import { z } from "zod";
import { chunkFrame, type FromMac, type ToMac } from "../src/protocol";

/**
 * Links this Mac to a Pond Connect account and carries phone requests to the local Pond API.
 * The account password and the Pond token never leave this Mac: the service gets a stretched key, Pond's token is added here.
 */
const server = process.env.POND_CONNECT_URL ?? "https://ponds.worma.dev";
const pond = "http://127.0.0.1:41610";
const configDir = join(homedir(), "Library/Application Support/Pond Connect");
const configPath = join(configDir, "config.json");
const configSchema = z.object({
  email: z.string(),
  machineId: z.string().uuid(),
});
const chunkSize = 256 * 1024;

const keychain = {
  read(service: string): string {
    try {
      return execFileSync(
        "security",
        ["find-generic-password", "-s", service, "-a", "wormadev", "-w"],
        { encoding: "utf8" },
      ).trim();
    } catch {
      throw new Error(`Missing keychain item "${service}".`);
    }
  },
  write(service: string, value: string) {
    execFileSync("security", [
      "add-generic-password",
      "-U",
      "-s",
      service,
      "-a",
      "wormadev",
      "-w",
      value,
    ]);
  },
};

export function deriveKey(email: string, password: string): string {
  return pbkdf2Sync(
    password,
    `pond-connect:${email.trim().toLowerCase()}`,
    600_000,
    32,
    "sha256",
  ).toString("base64url");
}

async function call<T>(
  path: string,
  init: RequestInit & { token?: string } = {},
): Promise<T> {
  const response = await fetch(server + path, {
    ...init,
    headers: {
      "content-type": "application/json",
      ...(init.token ? { authorization: `Bearer ${init.token}` } : {}),
    },
  });
  const body = (await response.json()) as {
    data?: T;
    error?: { message: string };
  };
  if (!response.ok || body.data === undefined)
    throw new Error(
      body.error?.message ?? `Pond Connect answered ${response.status}.`,
    );
  return body.data;
}

async function link(mode: "signup" | "login", email: string) {
  const password = readFileSync(0, "utf8").replace(/\r?\n$/, "");
  if (!password) throw new Error("Pass the password on standard input.");
  const device = { kind: "mac", name: hostname() };
  const { token } = await call<{ token: string }>(`/v1/${mode}`, {
    method: "POST",
    body: JSON.stringify({ email, key: deriveKey(email, password), device }),
  });
  keychain.write("com.wormadev.pond-connect", token);
  const me = await call<{ machines: { id: string; name: string }[] }>(
    "/v1/me",
    { token },
  );
  const existing = me.machines.find((machine) => machine.name === device.name);
  const machineId =
    existing?.id ??
    (
      await call<{ id: string }>("/v1/machines", {
        method: "POST",
        token,
        body: JSON.stringify({ name: device.name }),
      })
    ).id;
  mkdirSync(configDir, { recursive: true });
  writeFileSync(
    configPath,
    JSON.stringify({ email: email.trim().toLowerCase(), machineId }, null, 2),
  );
  console.log(`Linked ${device.name} to ${email}.`);
}

async function answer(socket: WebSocket, request: ToMac, pondToken: string) {
  const send = (frame: FromMac) => socket.send(JSON.stringify(frame));
  try {
    if (!request.path.startsWith("/api/v2/"))
      throw new Error("outside the public API");
    const response = await fetch(pond + request.path, {
      method: request.method,
      headers: { ...request.headers, authorization: `Bearer ${pondToken}` },
      body: request.body ? Buffer.from(request.body, "base64") : undefined,
    });
    send({
      t: "res",
      id: request.id,
      status: response.status,
      headers: Object.fromEntries(response.headers),
    });
    for await (const part of response.body ?? []) {
      for (let offset = 0; offset < part.byteLength; offset += chunkSize) {
        socket.send(
          chunkFrame(request.id, part.subarray(offset, offset + chunkSize)),
        );
      }
    }
    send({ t: "end", id: request.id });
  } catch (error) {
    console.error(
      `request ${request.id} failed: ${error instanceof Error ? error.message : error}`,
    );
    send({ t: "err", id: request.id });
  }
}

function run() {
  const config = configSchema.parse(
    JSON.parse(readFileSync(configPath, "utf8")),
  );
  const token = keychain.read("com.wormadev.pond-connect");
  const pondToken = keychain.read("com.wormadev.pond-token");
  let delay = 1000;

  const connect = () => {
    const socket = new WebSocket(
      `${server.replace(/^http/, "ws")}/v1/machines/${config.machineId}/connect`,
      {
        headers: { authorization: `Bearer ${token}` },
      } as never,
    );
    let heartbeat: Timer | undefined;
    socket.addEventListener("open", () => {
      delay = 1000;
      console.log("connected");
      heartbeat = setInterval(() => socket.send("ping"), 30_000);
    });
    socket.addEventListener("message", (event) => {
      if (typeof event.data !== "string" || event.data === "pong") return;
      void answer(socket, JSON.parse(event.data) as ToMac, pondToken);
    });
    socket.addEventListener("close", () => {
      clearInterval(heartbeat);
      console.log(`disconnected, retrying in ${delay / 1000}s`);
      setTimeout(connect, delay);
      delay = Math.min(delay * 2, 60_000);
    });
  };
  connect();
}

if (import.meta.main) {
  const [command, email] = process.argv.slice(2);
  if (command === "run") run();
  else if ((command === "signup" || command === "login") && email)
    await link(command, email);
  else {
    console.error(
      "usage: connector signup <email> | login <email> (password on stdin) | run",
    );
    process.exit(1);
  }
}
