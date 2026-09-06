// Adapter registry. Resolve ATSType → adapter function.

import type { ATSAdapter, ATSType } from "../models.ts";
import { fetchGreenhouse } from "./greenhouse.ts";
import { fetchLever } from "./lever.ts";
import { fetchAshby } from "./ashby.ts";
import { fetchSmartRecruiters } from "./smartrecruiters.ts";
import { fetchRecruitee } from "./recruitee.ts";
import { fetchWorkday } from "./workday.ts";

export const ADAPTERS: Record<ATSType, ATSAdapter> = {
  greenhouse: fetchGreenhouse,
  lever: fetchLever,
  ashby: fetchAshby,
  smartrecruiters: fetchSmartRecruiters,
  recruitee: fetchRecruitee,
  workday: fetchWorkday,
};

export function getAdapter(ats_type: ATSType): ATSAdapter {
  const adapter = ADAPTERS[ats_type];
  if (!adapter) throw new Error(`No adapter registered for ATS type "${ats_type}"`);
  return adapter;
}
