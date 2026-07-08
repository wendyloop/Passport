// Adapter registry — dispatch fund.platform → adapter.

import { getroAdapter } from "./getro.ts";
import { considerAdapter } from "./consider.ts";
import type { BoardAdapter } from "./types.ts";

export function getBoardAdapter(platform: string | null): BoardAdapter | null {
  if (platform === "getro") return getroAdapter;
  if (platform === "consider") return considerAdapter;
  return null;
}
