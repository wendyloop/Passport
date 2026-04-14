import { useEffect } from "react";
import { ActivityIndicator, View } from "react-native";
import { router } from "expo-router";

import { useSessionContext } from "@/providers/session-provider";
import { theme } from "@/styles/theme";

export default function IndexScreen() {
  const { loading, profile, session } = useSessionContext();

  useEffect(() => {
    if (loading) {
      return;
    }

    if (!session) {
      router.replace("/sign-in");
      return;
    }

    if (!profile?.onboarding_complete || !profile.role) {
      router.replace("/onboarding");
      return;
    }

    router.replace(profile.role === "employer" ? "/feed" : "/profile");
  }, [loading, profile, session]);

  return (
    <View
      style={{
        flex: 1,
        alignItems: "center",
        justifyContent: "center",
        backgroundColor: theme.colors.background,
      }}
    >
      <ActivityIndicator color={theme.colors.primary} />
    </View>
  );
}
