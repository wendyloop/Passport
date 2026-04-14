import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";

import { SessionProvider } from "@/providers/session-provider";
import { theme } from "@/styles/theme";

export default function RootLayout() {
  return (
    <SessionProvider>
      <StatusBar style="light" />
      <Stack
        screenOptions={{
          headerShown: false,
          contentStyle: {
            backgroundColor: theme.colors.background,
          },
        }}
      >
        <Stack.Screen name="index" />
        <Stack.Screen name="sign-in" />
        <Stack.Screen name="onboarding" />
        <Stack.Screen name="auth/callback" />
        <Stack.Screen name="notifications" />
        <Stack.Screen name="(jobseeker)" />
        <Stack.Screen name="(employer)" />
      </Stack>
    </SessionProvider>
  );
}
