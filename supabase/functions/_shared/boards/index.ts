// Board crawler registry. Resolve fund.platform → crawler.

import { crawlGetro } from "./getro.ts";
import { crawlConsider } from "./consider.ts";
import type { BoardCrawler } from "./models.ts";

export const CRAWLERS: Record<"getro" | "consider", BoardCrawler> = {
  getro: crawlGetro,
  consider: crawlConsider,
};

export function getCrawler(platform: string | null): BoardCrawler | null {
  if (platform === "getro" || platform === "consider") {
    return CRAWLERS[platform];
  }
  return null;
}
