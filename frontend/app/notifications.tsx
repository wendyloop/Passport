import { useEffect, useState } from "react";
import { Alert, Pressable, StyleSheet, Text, View } from "react-native";

import { Screen } from "@/components/screen";
import { supabase } from "@/lib/supabase";
import { theme } from "@/styles/theme";

type NotificationRow = {
  id: string;
  title: string;
  body: string;
  created_at: string;
  read_at: string | null;
};

export default function NotificationsScreen() {
  const [items, setItems] = useState<NotificationRow[]>([]);

  const loadNotifications = async () => {
    const { data, error } = await supabase
      .from("notifications")
      .select("id, title, body, created_at, read_at")
      .order("created_at", { ascending: false });

    if (error) {
      Alert.alert("Unable to load notifications", error.message);
      return;
    }

    setItems(data ?? []);
  };

  useEffect(() => {
    loadNotifications();
  }, []);

  const markAllRead = async () => {
    const unreadIds = items.filter((item) => !item.read_at).map((item) => item.id);
    if (!unreadIds.length) {
      return;
    }

    const { error } = await supabase.rpc("mark_notifications_read", {
      p_notification_ids: unreadIds,
    });

    if (error) {
      Alert.alert("Unable to mark notifications as read", error.message);
      return;
    }

    await loadNotifications();
  };

  return (
    <Screen
      title="Notifications"
      subtitle="Requests, approvals, and scheduling changes land here in realtime."
      rightAction={
        <Pressable onPress={markAllRead}>
          <Text style={styles.action}>Mark all read</Text>
        </Pressable>
      }
    >
      {items.map((item) => (
        <View key={item.id} style={[styles.card, !item.read_at && styles.cardUnread]}>
          <Text style={styles.cardTitle}>{item.title}</Text>
          <Text style={styles.cardBody}>{item.body}</Text>
        </View>
      ))}
    </Screen>
  );
}

const styles = StyleSheet.create({
  action: {
    color: theme.colors.primary,
    fontWeight: "700",
  },
  card: {
    backgroundColor: theme.colors.card,
    padding: theme.spacing.lg,
    borderRadius: theme.radius.md,
    gap: 8,
    borderWidth: 1,
    borderColor: theme.colors.border,
  },
  cardUnread: {
    borderColor: theme.colors.accent,
  },
  cardTitle: {
    color: theme.colors.text,
    fontSize: 17,
    fontWeight: "700",
  },
  cardBody: {
    color: theme.colors.textMuted,
    fontSize: 14,
    lineHeight: 20,
  },
});
