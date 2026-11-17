/** Frames between the relay and the Mac. Control frames are JSON text; body chunks are binary, prefixed by the request id. */
export type ToMac = {
  t: "req";
  id: number;
  method: string;
  path: string;
  headers: Record<string, string>;
  body?: string;
};

export type FromMac =
  | { t: "res"; id: number; status: number; headers: Record<string, string> }
  | { t: "end"; id: number }
  | { t: "err"; id: number };

export const forwardedRequestHeaders = [
  "content-type",
  "accept",
  "range",
  "if-none-match",
];
export const forwardedResponseHeaders = [
  "content-type",
  "content-length",
  "content-disposition",
  "content-range",
  "accept-ranges",
  "cache-control",
  "etag",
];

export function chunkFrame(id: number, chunk: Uint8Array): Uint8Array {
  const frame = new Uint8Array(4 + chunk.byteLength);
  new DataView(frame.buffer).setUint32(0, id);
  frame.set(chunk, 4);
  return frame;
}

export function readChunkFrame(frame: ArrayBuffer): {
  id: number;
  chunk: Uint8Array;
} {
  return {
    id: new DataView(frame).getUint32(0),
    chunk: new Uint8Array(frame, 4),
  };
}
