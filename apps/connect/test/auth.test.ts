import { env, SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

const key = (letter: string) => letter.repeat(43);
let ip = 0;

async function call(
  path: string,
  init: {
    method?: string;
    token?: string;
    body?: unknown;
    headers?: Record<string, string>;
  } = {},
) {
  const response = await SELF.fetch(`https://connect.test${path}`, {
    method: init.method ?? "GET",
    headers: {
      "content-type": "application/json",
      "cf-connecting-ip": `10.0.0.${ip}`,
      ...(init.token ? { authorization: `Bearer ${init.token}` } : {}),
      ...init.headers,
    },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
  const body = (await response.json()) as {
    data?: Record<string, unknown>;
    error?: { code: string };
  };
  return { status: response.status, data: body.data, code: body.error?.code };
}

async function account(
  email: string,
  kind: "mac" | "phone" = "mac",
  secret = key("a"),
) {
  ip += 1;
  const created = await call("/v1/signup", {
    method: "POST",
    body: { email, key: secret, device: { kind, name: "Test" } },
  });
  return created.data?.token as string;
}

describe("accounts", () => {
  it("creates an account and stores no usable secret", async () => {
    const token = await account("store@example.com");
    expect(token).toBeTruthy();
    const user = await env.DB.prepare(
      "SELECT key_hash FROM users WHERE email = ?",
    )
      .bind("store@example.com")
      .first<{ key_hash: string }>();
    expect(user?.key_hash).not.toContain(key("a"));
    const session = await env.DB.prepare(
      "SELECT token_hash FROM sessions",
    ).first<{ token_hash: string }>();
    expect(session?.token_hash).not.toBe(token);
  });

  it("refuses a second account with the same email, whatever its case", async () => {
    await account("twice@example.com");
    ip += 1;
    const again = await call("/v1/signup", {
      method: "POST",
      body: {
        email: "Twice@Example.com",
        key: key("b"),
        device: { kind: "mac", name: "Test" },
      },
    });
    expect(again.status).toBe(409);
  });

  it("signs in with the right key and gives the same answer for a wrong key and an unknown email", async () => {
    await account("login@example.com");
    ip += 1;
    const device = { kind: "phone", name: "Phone" };
    const right = await call("/v1/login", {
      method: "POST",
      body: { email: "login@example.com", key: key("a"), device },
    });
    const wrong = await call("/v1/login", {
      method: "POST",
      body: { email: "login@example.com", key: key("b"), device },
    });
    const unknown = await call("/v1/login", {
      method: "POST",
      body: { email: "nobody@example.com", key: key("a"), device },
    });
    expect(right.status).toBe(200);
    expect([wrong.status, wrong.code]).toEqual([401, "wrong_credentials"]);
    expect([unknown.status, unknown.code]).toEqual([wrong.status, wrong.code]);
  });

  it("rejects a malformed key", async () => {
    ip += 1;
    const short = await call("/v1/signup", {
      method: "POST",
      body: {
        email: "short@example.com",
        key: "abc",
        device: { kind: "mac", name: "Test" },
      },
    });
    expect(short.status).toBe(400);
  });

  it("slows down repeated attempts on one email", async () => {
    await account("limit@example.com");
    const statuses: number[] = [];
    for (let attempt = 0; attempt < 12; attempt += 1) {
      ip += 1;
      const result = await call("/v1/login", {
        method: "POST",
        body: {
          email: "limit@example.com",
          key: key("z"),
          device: { kind: "phone", name: "Phone" },
        },
      });
      statuses.push(result.status);
    }
    expect(statuses).toContain(429);
  });
});

describe("sessions", () => {
  it("needs a session for everything else", async () => {
    expect((await call("/v1/me")).status).toBe(401);
    expect((await call("/v1/me", { token: "not-a-session" })).status).toBe(401);
    expect(
      (await call("/m/00000000-0000-4000-8000-000000000000/api/v2/saves"))
        .status,
    ).toBe(401);
  });

  it("ends a session on sign out", async () => {
    const token = await account("out@example.com");
    expect((await call("/v1/me", { token })).status).toBe(200);
    expect((await call("/v1/logout", { method: "POST", token })).status).toBe(
      200,
    );
    expect((await call("/v1/me", { token })).status).toBe(401);
  });
});

describe("machines", () => {
  it("lets only a Mac session link a Mac", async () => {
    const phone = await account("phone@example.com", "phone");
    expect(
      (
        await call("/v1/machines", {
          method: "POST",
          token: phone,
          body: { name: "Mac" },
        })
      ).status,
    ).toBe(403);
  });

  it("hides a Mac from every other account", async () => {
    const owner = await account("owner@example.com");
    const stranger = await account("stranger@example.com");
    const linked = await call("/v1/machines", {
      method: "POST",
      token: owner,
      body: { name: "Mac" },
    });
    const id = linked.data?.id as string;
    expect(
      (await call(`/m/${id}/api/v2/saves`, { token: stranger })).status,
    ).toBe(404);
    expect(
      (await call(`/v1/machines/${id}`, { method: "DELETE", token: stranger }))
        .status,
    ).toBe(404);
    expect(
      (
        await call(`/v1/machines/${id}/connect`, {
          token: stranger,
          headers: { upgrade: "websocket" },
        })
      ).status,
    ).toBe(404);
    const offline = await call(`/m/${id}/api/v2/saves`, { token: owner });
    expect([offline.status, offline.code]).toEqual([503, "mac_offline"]);
  });

  it("refuses a phone session on the Mac's socket", async () => {
    const mac = await account("socket@example.com");
    const linked = await call("/v1/machines", {
      method: "POST",
      token: mac,
      body: { name: "Mac" },
    });
    ip += 1;
    const login = await call("/v1/login", {
      method: "POST",
      body: {
        email: "socket@example.com",
        key: key("a"),
        device: { kind: "phone", name: "Phone" },
      },
    });
    const refused = await call(`/v1/machines/${linked.data?.id}/connect`, {
      token: login.data?.token as string,
      headers: { upgrade: "websocket" },
    });
    expect(refused.status).toBe(426);
  });

  it("accepts the Mac's token as a socket subprotocol", async () => {
    const mac = await account("protocol@example.com");
    const linked = await call("/v1/machines", {
      method: "POST",
      token: mac,
      body: { name: "Mac" },
    });
    const response = await SELF.fetch(
      `https://connect.test/v1/machines/${linked.data?.id}/connect`,
      {
        headers: {
          upgrade: "websocket",
          "sec-websocket-protocol": `pond-connect, bearer.${mac}`,
        },
      },
    );
    expect(response.status).toBe(101);
    expect(response.headers.get("sec-websocket-protocol")).toBe("pond-connect");
    response.webSocket?.accept();
    response.webSocket?.close();
  });
});
