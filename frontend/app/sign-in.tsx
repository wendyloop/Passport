import { useState } from "react";
import {
  Alert,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { router } from "expo-router";

import { Screen } from "@/components/screen";
import { signInWithGoogle, supabase } from "@/lib/supabase";
import { theme } from "@/styles/theme";

export default function SignInScreen() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [mode, setMode] = useState<"sign_in" | "sign_up">("sign_in");
  const [loading, setLoading] = useState(false);

  const handleEmailAuth = async () => {
    try {
      setLoading(true);

      const authCall =
        mode === "sign_in"
          ? supabase.auth.signInWithPassword({ email, password })
          : supabase.auth.signUp({ email, password });

      const { error } = await authCall;
      if (error) {
        throw error;
      }

      router.replace("/onboarding");
    } catch (error) {
      Alert.alert("Auth error", error instanceof Error ? error.message : "Unknown error");
    } finally {
      setLoading(false);
    }
  };

  const handleGoogle = async () => {
    try {
      setLoading(true);
      await signInWithGoogle();
      router.replace("/onboarding");
    } catch (error) {
      Alert.alert("Google sign-in error", error instanceof Error ? error.message : "Unknown error");
    } finally {
      setLoading(false);
    }
  };

  return (
    <Screen
      title="Passport"
      subtitle="Swipe through candidates, manage interviews, and build a verified hiring network."
      scroll={false}
    >
      <View style={styles.hero}>
        <Text style={styles.heroTitle}>Mobile-first hiring for short-form video.</Text>
        <Text style={styles.heroBody}>
          Job seekers create a concise intro profile. Employers browse a fast feed,
          save candidates, and move directly into interview scheduling.
        </Text>
      </View>

      <View style={styles.card}>
        <View style={styles.toggleRow}>
          {(["sign_in", "sign_up"] as const).map((value) => (
            <Pressable
              key={value}
              onPress={() => setMode(value)}
              style={[styles.modeButton, mode === value && styles.modeButtonActive]}
            >
              <Text style={styles.modeLabel}>
                {value === "sign_in" ? "Sign in" : "Create account"}
              </Text>
            </Pressable>
          ))}
        </View>

        <TextInput
          autoCapitalize="none"
          keyboardType="email-address"
          onChangeText={setEmail}
          placeholder="Email"
          placeholderTextColor={theme.colors.textMuted}
          style={styles.input}
          value={email}
        />
        <TextInput
          onChangeText={setPassword}
          placeholder="Password"
          placeholderTextColor={theme.colors.textMuted}
          secureTextEntry
          style={styles.input}
          value={password}
        />

        <Pressable disabled={loading} onPress={handleEmailAuth} style={styles.primaryButton}>
          <Text style={styles.primaryButtonText}>
            {mode === "sign_in" ? "Continue" : "Create account"}
          </Text>
        </Pressable>

        <Pressable disabled={loading} onPress={handleGoogle} style={styles.secondaryButton}>
          <Text style={styles.secondaryButtonText}>Continue with Google</Text>
        </Pressable>
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  hero: {
    gap: theme.spacing.sm,
    marginTop: theme.spacing.lg,
  },
  heroTitle: {
    color: theme.colors.text,
    fontSize: 36,
    fontWeight: "700",
    lineHeight: 42,
  },
  heroBody: {
    color: theme.colors.textMuted,
    fontSize: 16,
    lineHeight: 24,
  },
  card: {
    marginTop: theme.spacing.xl,
    backgroundColor: theme.colors.card,
    borderRadius: theme.radius.lg,
    padding: theme.spacing.lg,
    gap: theme.spacing.md,
    borderWidth: 1,
    borderColor: theme.colors.border,
  },
  toggleRow: {
    flexDirection: "row",
    gap: theme.spacing.sm,
  },
  modeButton: {
    flex: 1,
    borderRadius: theme.radius.sm,
    paddingVertical: 12,
    backgroundColor: theme.colors.surface,
    alignItems: "center",
  },
  modeButtonActive: {
    backgroundColor: theme.colors.primary,
  },
  modeLabel: {
    color: theme.colors.text,
    fontWeight: "600",
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
  primaryButton: {
    backgroundColor: theme.colors.primary,
    paddingVertical: 16,
    borderRadius: theme.radius.sm,
    alignItems: "center",
  },
  primaryButtonText: {
    color: "#2c1200",
    fontWeight: "700",
    fontSize: 16,
  },
  secondaryButton: {
    paddingVertical: 16,
    borderRadius: theme.radius.sm,
    alignItems: "center",
    borderWidth: 1,
    borderColor: theme.colors.border,
  },
  secondaryButtonText: {
    color: theme.colors.text,
    fontWeight: "600",
    fontSize: 16,
  },
});
