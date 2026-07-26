// Pure profile-side gate decision for send-founder-email, shared between
// preview and send so both modes always agree. Order matters: the preview
// surfaces exactly one reason, and the cheapest thing the candidate can fix
// comes first.

export type FounderGateInput = {
  hasPitchVideo: boolean;
  hasResume: boolean;
  requireResume: boolean;
};

export type FounderGateReason = "pitch_video_required" | "resume_required";

export function founderProfileGateReason(input: FounderGateInput): FounderGateReason | null {
  if (!input.hasPitchVideo) return "pitch_video_required";
  if (input.requireResume && !input.hasResume) return "resume_required";
  return null;
}
