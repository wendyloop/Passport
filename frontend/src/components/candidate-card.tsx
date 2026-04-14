import { Pressable, StyleSheet, Text, View } from "react-native";
import { LinearGradient } from "expo-linear-gradient";

import { CandidateFeedItem } from "@/types/database";
import { theme } from "@/styles/theme";

type CandidateCardProps = {
  item: CandidateFeedItem;
  onLike: (candidateId: string) => Promise<void>;
};

export function CandidateCard({ item, onLike }: CandidateCardProps) {
  let lastTap = 0;

  const handlePress = async () => {
    const now = Date.now();
    if (now - lastTap < 300) {
      await onLike(item.candidate_id);
    }
    lastTap = now;
  };

  return (
    <Pressable onPress={handlePress} style={styles.shell}>
      <LinearGradient
        colors={["#15345a", "#0b1628", "#0a1020"]}
        style={styles.video}
      >
        <View style={styles.badges}>
          {item.referral_badge ? (
            <View style={styles.badge}>
              <Text style={styles.badgeText}>Referral</Text>
            </View>
          ) : null}
          {item.job_function ? (
            <View style={styles.badgeMuted}>
              <Text style={styles.badgeMutedText}>{item.job_function}</Text>
            </View>
          ) : null}
        </View>

        <View style={styles.meta}>
          <Text style={styles.name}>{item.full_name}</Text>
          {item.headline ? <Text style={styles.headline}>{item.headline}</Text> : null}
          {item.school_name ? (
            <Text style={styles.detail}>School: {item.school_name}</Text>
          ) : null}
          {item.previous_employers?.length ? (
            <Text style={styles.detail}>
              Previous employers: {item.previous_employers.join(", ")}
            </Text>
          ) : null}
          <Text style={styles.hint}>Double tap to like and send an interview request.</Text>
        </View>
      </LinearGradient>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  shell: {
    borderRadius: theme.radius.lg,
    overflow: "hidden",
  },
  video: {
    minHeight: 520,
    padding: theme.spacing.lg,
    justifyContent: "space-between",
  },
  badges: {
    flexDirection: "row",
    gap: theme.spacing.sm,
  },
  badge: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    backgroundColor: theme.colors.accent,
    borderRadius: 999,
  },
  badgeText: {
    color: "#062316",
    fontWeight: "700",
    textTransform: "uppercase",
    fontSize: 11,
  },
  badgeMuted: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    backgroundColor: "rgba(255,255,255,0.12)",
    borderRadius: 999,
  },
  badgeMutedText: {
    color: theme.colors.text,
    fontWeight: "600",
    textTransform: "capitalize",
  },
  meta: {
    gap: 8,
  },
  name: {
    color: theme.colors.text,
    fontSize: 28,
    fontWeight: "700",
  },
  headline: {
    color: theme.colors.text,
    fontSize: 18,
    fontWeight: "500",
  },
  detail: {
    color: theme.colors.textMuted,
    fontSize: 15,
    lineHeight: 22,
  },
  hint: {
    color: theme.colors.primary,
    fontSize: 13,
    fontWeight: "600",
    marginTop: 8,
  },
});
