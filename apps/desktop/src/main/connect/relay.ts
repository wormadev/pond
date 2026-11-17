import log from "electron-log/main.js";
import { z } from "zod";
import { CONNECT_SERVER, DEFAULT_INGEST_PORT } from "../../shared/constants";
import { getPrefs } from "../core/prefs";

const CHUNK_BYTES = 256 * 1024;
const BUFFER_LIMIT_BYTES = 8 * 1024 * 1024;
const HEARTBEAT_MS = 30_000;
const MAX_RETRY_MS = 60_000;

const RequestFrameSchema = z.object({
  t: z.literal("req"),
  id: z.number().int().nonnegative(),
  method: z.string(),
  path: z.string(),
  headers: z.record(z.string(), z.string()),
  body: z.string().optional(),
});
type RequestFrame = z.infer<typeof RequestFrameSchema>;

interface RelayOptions {
  machineId: string;
  token: string;
  apiToken: string;
  /** The socket closed before it ever opened, which is how a revoked session shows up. */
  onRejected: () => void;
}

function chunkFrame(id: number, chunk: Uint8Array): Uint8Array<ArrayBuffer> {
  const frame = new Uint8Array(4 + chunk.byteLength);
  new DataView(frame.buffer).setUint32(0, id);
  frame.set(chunk, 4);
  return frame;
}

async function drained(socket: WebSocket): Promise<void> {
  while (
    socket.readyState === WebSocket.OPEN &&
    socket.bufferedAmount > BUFFER_LIMIT_BYTES
  ) {
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
}

async function answer(
  socket: WebSocket,
  request: RequestFrame,
  apiToken: string,
): Promise<void> {
  try {
    if (!request.path.startsWith("/api/v2/")) {
      throw new Error("outside the public API");
    }
    const prefs = await getPrefs();
    const port = prefs.api.port || DEFAULT_INGEST_PORT;
    const response = await fetch(`http://127.0.0.1:${port}${request.path}`, {
      method: request.method,
      headers: { ...request.headers, authorization: `Bearer ${apiToken}` },
      body: request.body ? Buffer.from(request.body, "base64") : undefined,
    });
    socket.send(
      JSON.stringify({
        t: "res",
        id: request.id,
        status: response.status,
        headers: Object.fromEntries(response.headers),
      }),
    );
    for await (const part of response.body ?? []) {
      for (let offset = 0; offset < part.byteLength; offset += CHUNK_BYTES) {
        await drained(socket);
        socket.send(
          chunkFrame(request.id, part.subarray(offset, offset + CHUNK_BYTES)),
        );
      }
    }
    socket.send(JSON.stringify({ t: "end", id: request.id }));
  } catch (cause) {
    log.warn("[pond connect] request failed", cause);
    if (socket.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify({ t: "err", id: request.id }));
    }
  }
}

/** Keeps one outbound socket to the relay and answers each phone request from the local API. */
export function openRelay(options: RelayOptions) {
  const url = `${CONNECT_SERVER.replace(/^http/, "ws")}/v1/machines/${options.machineId}/connect`;
  let socket: WebSocket | null = null;
  let retry: NodeJS.Timeout | undefined;
  let closed = false;
  let delay = 1000;

  function connect() {
    let opened = false;
    let heartbeat: NodeJS.Timeout | undefined;
    const current = new WebSocket(url, [
      "pond-connect",
      `bearer.${options.token}`,
    ]);
    current.binaryType = "arraybuffer";
    socket = current;
    current.addEventListener("open", () => {
      opened = true;
      delay = 1000;
      heartbeat = setInterval(() => current.send("ping"), HEARTBEAT_MS);
    });
    current.addEventListener("message", (event) => {
      if (typeof event.data !== "string" || event.data === "pong") return;
      const frame = RequestFrameSchema.safeParse(JSON.parse(event.data));
      if (frame.success) void answer(current, frame.data, options.apiToken);
    });
    current.addEventListener("close", () => {
      clearInterval(heartbeat);
      if (closed) return;
      if (!opened) options.onRejected();
      retry = setTimeout(connect, delay);
      delay = Math.min(delay * 2, MAX_RETRY_MS);
    });
  }
  connect();

  return {
    isOpen: () => socket?.readyState === WebSocket.OPEN,
    close() {
      closed = true;
      clearTimeout(retry);
      socket?.close();
    },
  };
}
