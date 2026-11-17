import { z } from "zod";
import {
  connectSignIn,
  connectSignOut,
  connectStatus,
} from "../../connect/session";
import { type QueryHandlerMap, query } from "./params";

export const connectQueries = {
  "connect.status": () => connectStatus(),

  "connect.signIn": query(
    z.object({
      email: z.email().max(254),
      password: z.string().min(10).max(1024),
      creating: z.boolean(),
    }),
    connectSignIn,
  ),

  "connect.signOut": () => connectSignOut(),
} satisfies QueryHandlerMap;
