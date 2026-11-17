import { DurableObject } from "cloudflare:workers";
import type { Env } from "./index";
import {
  type FromMac,
  forwardedRequestHeaders,
  forwardedResponseHeaders,
  readChunkFrame,
  type ToMac,
} from "./protocol";

const relayProtocol = "pond-connect";
const maxRequestBody = 256 * 1024;
const headersTimeoutMs = 30_000;

interface Pending {
  respond: (response: Response) => void;
  body?: WritableStreamDefaultWriter<Uint8Array>;
}

/** One per Mac. Holds the Mac's socket and passes each phone request through it. Nothing is stored. */
export class Relay extends DurableObject<Env> {
  private pending = new Map<number, Pending>();
  private nextId = 1;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.setWebSocketAutoResponse(
      new WebSocketRequestResponsePair("ping", "pong"),
    );
  }

  isOnline(): boolean {
    return this.ctx.getWebSockets().length > 0;
  }

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("upgrade") === "websocket") {
      return this.attachMac(
        (request.headers.get("sec-websocket-protocol") ?? "").includes(
          relayProtocol,
        ),
      );
    }
    return this.forward(request);
  }

  private attachMac(namedProtocol: boolean): Response {
    for (const old of this.ctx.getWebSockets()) old.close(1012, "replaced");
    const [client, server] = Object.values(new WebSocketPair()) as [
      WebSocket,
      WebSocket,
    ];
    this.ctx.acceptWebSocket(server);
    const headers = namedProtocol
      ? { "sec-websocket-protocol": relayProtocol }
      : undefined;
    return new Response(null, { status: 101, webSocket: client, headers });
  }

  private async forward(request: Request): Promise<Response> {
    const mac = this.ctx.getWebSockets()[0];
    if (!mac)
      return failure(
        503,
        "mac_offline",
        "Your Mac isn't connected. Open Pond on it.",
      );
    const body = request.body
      ? new Uint8Array(await request.arrayBuffer())
      : undefined;
    if (body && body.byteLength > maxRequestBody)
      return failure(413, "too_large", "That request is too large.");

    const id = this.nextId++;
    const headers: Record<string, string> = {};
    for (const name of forwardedRequestHeaders) {
      const value = request.headers.get(name);
      if (value) headers[name] = value;
    }
    const frame: ToMac = {
      t: "req",
      id,
      method: request.method,
      path: request.headers.get("x-relay-path") ?? "/",
      headers,
      body: body?.byteLength ? btoa(String.fromCharCode(...body)) : undefined,
    };

    const response = new Promise<Response>((respond) =>
      this.pending.set(id, { respond }),
    );
    mac.send(JSON.stringify(frame));
    const timeout = new Promise<Response>((resolve) =>
      setTimeout(
        () =>
          resolve(
            failure(504, "mac_timeout", "Your Mac took too long to answer."),
          ),
        headersTimeoutMs,
      ),
    );
    const result = await Promise.race([response, timeout]);
    if (result.status === 504) this.pending.delete(id);
    return result;
  }

  async webSocketMessage(
    _socket: WebSocket,
    message: string | ArrayBuffer,
  ): Promise<void> {
    if (typeof message !== "string") {
      const { id, chunk } = readChunkFrame(message);
      await this.pending.get(id)?.body?.write(chunk);
      return;
    }
    const frame = JSON.parse(message) as FromMac;
    const entry = this.pending.get(frame.id);
    if (!entry) return;
    if (frame.t === "res") {
      const { readable, writable } = new TransformStream<
        Uint8Array,
        Uint8Array
      >();
      entry.body = writable.getWriter();
      const headers = new Headers();
      for (const name of forwardedResponseHeaders) {
        const value = frame.headers[name];
        if (value) headers.set(name, value);
      }
      entry.respond(
        new Response(
          frame.status === 204 || frame.status === 304 ? null : readable,
          { status: frame.status, headers },
        ),
      );
    } else {
      this.pending.delete(frame.id);
      if (frame.t === "end") await entry.body?.close();
      else if (entry.body) await entry.body.abort("mac_error");
      else
        entry.respond(
          failure(502, "mac_error", "Pond on your Mac couldn't answer that."),
        );
    }
  }

  async webSocketClose(): Promise<void> {
    for (const [id, entry] of this.pending) {
      this.pending.delete(id);
      if (entry.body) await entry.body.abort("mac_disconnected");
      else entry.respond(failure(503, "mac_offline", "Your Mac disconnected."));
    }
  }
}

export function failure(
  status: number,
  code: string,
  message: string,
): Response {
  return Response.json(
    { status: "error", error: { code, message } },
    { status },
  );
}
