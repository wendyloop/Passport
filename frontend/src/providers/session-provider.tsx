import {
  PropsWithChildren,
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";

import { Session } from "@supabase/supabase-js";

import { supabase } from "@/lib/supabase";
import { AppProfile } from "@/types/database";

type SessionContextValue = {
  session: Session | null;
  profile: AppProfile | null;
  loading: boolean;
  refreshProfile: () => Promise<void>;
  signOut: () => Promise<void>;
};

const SessionContext = createContext<SessionContextValue | null>(null);

async function fetchProfile(userId: string) {
  const { data, error } = await supabase
    .from("profiles")
    .select(
      `
        id,
        role,
        full_name,
        email,
        avatar_url,
        headline,
        onboarding_complete,
        employer_profiles (
          company_name,
          company_domain,
          position_title,
          calendar_connected
        ),
        job_seeker_profiles (
          school_name,
          job_function,
          referral_badge,
          intro_video_url
        )
      `,
    )
    .eq("id", userId)
    .single();

  if (error) {
    throw error;
  }

  return {
    ...data,
    employer_profiles: Array.isArray(data.employer_profiles)
      ? data.employer_profiles[0] ?? null
      : data.employer_profiles,
    job_seeker_profiles: Array.isArray(data.job_seeker_profiles)
      ? data.job_seeker_profiles[0] ?? null
      : data.job_seeker_profiles,
  } as AppProfile;
}

export function SessionProvider({ children }: PropsWithChildren) {
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<AppProfile | null>(null);
  const [loading, setLoading] = useState(true);

  const refreshProfile = async () => {
    const userId = session?.user.id;
    if (!userId) {
      setProfile(null);
      return;
    }

    const nextProfile = await fetchProfile(userId);
    setProfile(nextProfile);
  };

  useEffect(() => {
    supabase.auth.getSession().then(async ({ data }) => {
      const nextSession = data.session;
      setSession(nextSession);

      if (nextSession?.user.id) {
        try {
          setProfile(await fetchProfile(nextSession.user.id));
        } finally {
          setLoading(false);
        }
      } else {
        setLoading(false);
      }
    });

    const { data: listener } = supabase.auth.onAuthStateChange(
      async (_event, nextSession) => {
        setSession(nextSession);

        if (nextSession?.user.id) {
          try {
            setProfile(await fetchProfile(nextSession.user.id));
          } finally {
            setLoading(false);
          }
        } else {
          setProfile(null);
          setLoading(false);
        }
      },
    );

    return () => {
      listener.subscription.unsubscribe();
    };
  }, []);

  const value = useMemo<SessionContextValue>(
    () => ({
      session,
      profile,
      loading,
      refreshProfile,
      signOut: async () => {
        await supabase.auth.signOut();
      },
    }),
    [loading, profile, session],
  );

  return (
    <SessionContext.Provider value={value}>{children}</SessionContext.Provider>
  );
}

export function useSessionContext() {
  const context = useContext(SessionContext);
  if (!context) {
    throw new Error("useSessionContext must be used inside SessionProvider.");
  }

  return context;
}
