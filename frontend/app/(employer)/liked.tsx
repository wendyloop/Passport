import { useEffect, useState } from "react";
import { Alert, StyleSheet, Text, View } from "react-native";

import { Screen } from "@/components/screen";
import { supabase } from "@/lib/supabase";
import { CandidateFeedItem } from "@/types/database";
import { theme } from "@/styles/theme";

export default function EmployerLikedScreen() {
  const [items, setItems] = useState<CandidateFeedItem[]>([]);

  const loadData = async () => {
    const { data: likes, error: likesError } = await supabase
      .from("candidate_likes")
      .select("candidate_profile_id");

    if (likesError) {
      Alert.alert("Unable to load likes", likesError.message);
      return;
    }

    const likedIds = (likes ?? []).map((row) => row.candidate_profile_id);
    if (!likedIds.length) {
      setItems([]);
      return;
    }

    const { data: feedItems, error: feedError } = await supabase
      .from("candidate_feed")
      .select("*")
      .in("candidate_id", likedIds);

    if (feedError) {
      Alert.alert("Unable to load liked candidates", feedError.message);
      return;
    }

    setItems((feedItems ?? []) as CandidateFeedItem[]);
  };

  useEffect(() => {
    loadData();
  }, []);

  return (
    <Screen
      title="Liked candidates"
      subtitle="Candidates you double tapped stay here so you can revisit their profile context."
    >
      {items.map((item) => (
        <View key={item.candidate_id} style={styles.card}>
          <Text style={styles.name}>{item.full_name}</Text>
          {item.headline ? <Text style={styles.headline}>{item.headline}</Text> : null}
          {item.school_name ? <Text style={styles.detail}>School: {item.school_name}</Text> : null}
          {item.previous_employers?.length ? (
            <Text style={styles.detail}>
              Previous employers: {item.previous_employers.join(", ")}
            </Text>
          ) : null}
        </View>
      ))}
    </Screen>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: theme.colors.card,
    borderRadius: theme.radius.lg,
    padding: theme.spacing.lg,
    gap: 8,
    borderWidth: 1,
    borderColor: theme.colors.border,
  },
  name: {
    color: theme.colors.text,
    fontSize: 20,
    fontWeight: "700",
  },
  headline: {
    color: theme.colors.text,
    fontSize: 15,
    fontWeight: "500",
  },
  detail: {
    color: theme.colors.textMuted,
    fontSize: 14,
    lineHeight: 20,
  },
});
