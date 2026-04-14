export type AppRole = "job_seeker" | "employer";

export type JobFunction =
  | "engineering"
  | "design"
  | "product"
  | "science"
  | "sales"
  | "marketing"
  | "support"
  | "operations"
  | "hr"
  | "finance"
  | "legal";

export type CandidateFeedItem = {
  candidate_id: string;
  full_name: string;
  headline: string | null;
  school_name: string | null;
  job_function: JobFunction | null;
  referral_badge: boolean;
  previous_employers: string[] | null;
  video_url: string | null;
  poster_url: string | null;
};

export type AppProfile = {
  id: string;
  role: AppRole | null;
  full_name: string | null;
  email: string | null;
  avatar_url: string | null;
  headline: string | null;
  onboarding_complete: boolean;
  employer_profiles?: {
    company_name: string | null;
    company_domain: string | null;
    position_title: string | null;
    calendar_connected: boolean;
  } | null;
  job_seeker_profiles?: {
    school_name: string | null;
    job_function: JobFunction | null;
    referral_badge: boolean;
    intro_video_url: string | null;
  } | null;
};
