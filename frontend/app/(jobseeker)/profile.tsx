import { Pressable, StyleSheet, Text, View } from "react-native";
import { router } from "expo-router";

import { Screen } from "@/components/screen";
import { useSessionContext } from "@/providers/session-provider";
import { theme } from "@/styles/theme";

export default function JobSeekerProfileScreen() {
  const { profile, signOut } = useSessionContext();

  return (
    <Screen
      title={profile?.full_name ?? "Your profile"}
      subtitle="This is the public profile employers review in the swipe feed."
      rightAction={
        <Pressable onPress={() => router.push("/notifications")}>
          <Text style={styles.action}>Notifications</Text>
        </Pressable>
      }
    >
      <View style={styles.hero}>
        <Text style={styles.headline}>{profile?.headline ?? "Add a concise intro headline."}</Text>
        <Text style={styles.body}>
          School: {profile?.job_seeker_profiles?.school_name ?? "Not added yet"}
        </Text>
        <Text style={styles.body}>
          Function: {profile?.job_seeker_profiles?.job_function ?? "Not added yet"}
        </Text>
        <Text style={styles.body}>
          Referral badge: {profile?.job_seeker_profiles?.referral_badge ? "Yes" : "No"}
        </Text>
      </View>

      <View style={styles.card}>
        <Text style={styles.cardTitle}>Video profile</Text>
        <Text style={styles.cardBody}>
          The intro video upload is stored on the backend and surfaced into the employer feed.
        </Text>
      </View>

      <Pressable onPress={signOut} style={styles.button}>
        <Text style={styles.buttonText}>Sign out</Text>
      </Pressable>
    </Screen>
  );
}

const styles = StyleSheet.create({
  action: {
    color: theme.colors.primary,
    fontWeight: "700",
  },
  hero: {
    backgroundColor: theme.colors.card,
    borderRadius: theme.radius.lg,
    padding: theme.spacing.lg,
    borderWidth: 1,
    borderColor: theme.colors.border,
    gap: 10,
  },
  headline: {
    color: theme.colors.text,
    fontSize: 24,
    fontWeight: "700",
    lineHeight: 30,
  },
  body: {
    color: theme.colors.textMuted,
    fontSize: 15,
    lineHeight: 22,
  },
  card: {
    backgroundColor: theme.colors.surface,
    borderRadius: theme.radius.md,
    padding: theme.spacing.lg,
    gap: 8,
  },
  cardTitle: {
    color: theme.colors.text,
    fontSize: 18,
    fontWeight: "700",
  },
  cardBody: {
    color: theme.colors.textMuted,
    fontSize: 14,
    lineHeight: 20,
  },
  button: {
    backgroundColor: theme.colors.danger,
    borderRadius: theme.radius.sm,
    alignItems: "center",
    paddingVertical: 15,
  },
  buttonText: {
    color: "#fff3f5",
    fontWeight: "700",
  },
});
