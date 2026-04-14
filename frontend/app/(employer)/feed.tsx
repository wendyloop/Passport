import { useEffect, useMemo, useState } from "react";
import { Alert, Pressable, StyleSheet, Text, TextInput, View } from "react-native";
import { router } from "expo-router";

import { CandidateCard } from "@/components/candidate-card";
import { Screen } from "@/components/screen";
import { supabase } from "@/lib/supabase";
import { CandidateFeedItem } from "@/types/database";
import { theme } from "@/styles/theme";

export default function EmployerFeedScreen() {
  const [items, setItems] = useState<CandidateFeedItem[]>([]);
  const [schoolFilter, setSchoolFilter] = useState("");
  const [employerFilter, setEmployerFilter] = useState("");
  const [jobFunctionFilter, setJobFunctionFilter] = useState("");
  const [referralOnly, setReferralOnly] = useState(false);

  const loadFeed = async () => {
    const { data, error } = await supabase
      .from("candidate_feed")
      .select("*")
      .order("full_name", { ascending: true });

    if (error) {
      Alert.alert("Unable to load candidate feed", error.message);
      return;
    }

    setItems((data ?? []) as CandidateFeedItem[]);
  };

  useEffect(() => {
    loadFeed();
  }, []);

  const visibleItems = useMemo(() => {
    return items.filter((item) => {
      const matchesSchool =
        !schoolFilter ||
        item.school_name?.toLowerCase().includes(schoolFilter.toLowerCase());
      const matchesEmployer =
        !employerFilter ||
        item.previous_employers?.some((employer) =>
          employer.toLowerCase().includes(employerFilter.toLowerCase()),
        );
      const matchesFunction =
        !jobFunctionFilter ||
        item.job_function?.toLowerCase().includes(jobFunctionFilter.toLowerCase());
      const matchesReferral = !referralOnly || item.referral_badge;

      return matchesSchool && matchesEmployer && matchesFunction && matchesReferral;
    });
  }, [employerFilter, items, jobFunctionFilter, referralOnly, schoolFilter]);

  const likeCandidate = async (candidateId: string) => {
    const { error } = await supabase.rpc("like_candidate", {
      p_candidate_profile_id: candidateId,
    });

    if (error) {
      Alert.alert("Unable to like candidate", error.message);
      return;
    }

    Alert.alert("Candidate saved", "An interview request was sent to the candidate.");
  };

  return (
    <Screen
      title="Candidate feed"
      subtitle="Scroll through short intro videos, filter candidates, and double tap to like."
      rightAction={
        <Pressable onPress={() => router.push("/notifications")}>
          <Text style={styles.action}>Notifications</Text>
        </Pressable>
      }
    >
      <View style={styles.filters}>
        <TextInput
          onChangeText={setSchoolFilter}
          placeholder="Filter by school"
          placeholderTextColor={theme.colors.textMuted}
          style={styles.input}
          value={schoolFilter}
        />
        <TextInput
          onChangeText={setEmployerFilter}
          placeholder="Filter by previous employer"
          placeholderTextColor={theme.colors.textMuted}
          style={styles.input}
          value={employerFilter}
        />
        <TextInput
          onChangeText={setJobFunctionFilter}
          placeholder="Filter by job function"
          placeholderTextColor={theme.colors.textMuted}
          style={styles.input}
          value={jobFunctionFilter}
        />
        <Pressable
          onPress={() => setReferralOnly((value) => !value)}
          style={[styles.referralToggle, referralOnly && styles.referralToggleActive]}
        >
          <Text style={styles.referralToggleText}>Referral only</Text>
        </Pressable>
      </View>

      {visibleItems.map((item) => (
        <CandidateCard item={item} key={item.candidate_id} onLike={likeCandidate} />
      ))}
    </Screen>
  );
}

const styles = StyleSheet.create({
  action: {
    color: theme.colors.primary,
    fontWeight: "700",
  },
  filters: {
    gap: theme.spacing.sm,
  },
  input: {
    backgroundColor: theme.colors.surfaceMuted,
    borderRadius: theme.radius.sm,
    paddingHorizontal: 16,
    paddingVertical: 14,
    color: theme.colors.text,
    borderWidth: 1,
    borderColor: theme.colors.border,
  },
  referralToggle: {
    backgroundColor: theme.colors.surface,
    borderRadius: theme.radius.sm,
    paddingVertical: 14,
    alignItems: "center",
    borderWidth: 1,
    borderColor: theme.colors.border,
  },
  referralToggleActive: {
    backgroundColor: theme.colors.accent,
    borderColor: theme.colors.accent,
  },
  referralToggleText: {
    color: theme.colors.text,
    fontWeight: "600",
  },
});
