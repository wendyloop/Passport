import { PropsWithChildren, ReactNode } from "react";
import {
  ActivityIndicator,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { theme } from "@/styles/theme";

type ScreenProps = PropsWithChildren<{
  title: string;
  subtitle?: string;
  rightAction?: ReactNode;
  scroll?: boolean;
  loading?: boolean;
}>;

export function Screen({
  children,
  loading,
  rightAction,
  scroll = true,
  subtitle,
  title,
}: ScreenProps) {
  const body = loading ? (
    <View style={styles.center}>
      <ActivityIndicator color={theme.colors.primary} />
    </View>
  ) : (
    children
  );

  return (
    <SafeAreaView style={styles.safeArea}>
      <View style={styles.header}>
        <View style={styles.headerCopy}>
          <Text style={styles.title}>{title}</Text>
          {subtitle ? <Text style={styles.subtitle}>{subtitle}</Text> : null}
        </View>
        {rightAction}
      </View>
      {scroll ? (
        <ScrollView contentContainerStyle={styles.content}>{body}</ScrollView>
      ) : (
        <View style={styles.content}>{body}</View>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: theme.colors.background,
  },
  header: {
    paddingHorizontal: theme.spacing.lg,
    paddingTop: theme.spacing.sm,
    paddingBottom: theme.spacing.md,
    flexDirection: "row",
    alignItems: "flex-start",
    justifyContent: "space-between",
  },
  headerCopy: {
    flex: 1,
    gap: 6,
  },
  title: {
    color: theme.colors.text,
    fontSize: 30,
    fontWeight: "700",
  },
  subtitle: {
    color: theme.colors.textMuted,
    fontSize: 14,
    lineHeight: 20,
  },
  content: {
    paddingHorizontal: theme.spacing.lg,
    paddingBottom: theme.spacing.xl,
    gap: theme.spacing.md,
  },
  center: {
    minHeight: 280,
    justifyContent: "center",
    alignItems: "center",
  },
});
