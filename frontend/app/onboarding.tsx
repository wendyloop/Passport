import { useMemo, useState } from "react";
import {
  Alert,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import * as DocumentPicker from "expo-document-picker";
import * as ImagePicker from "expo-image-picker";
import { router, useLocalSearchParams } from "expo-router";

import { Screen } from "@/components/screen";
import { invokeEdgeFunction, supabase } from "@/lib/supabase";
import { uploadFileToBucket } from "@/lib/storage";
import { useSessionContext } from "@/providers/session-provider";
import { JobFunction } from "@/types/database";
import { theme } from "@/styles/theme";

const jobFunctions: JobFunction[] = [
  "engineering",
  "design",
  "product",
  "science",
  "sales",
  "marketing",
  "support",
  "operations",
  "hr",
  "finance",
  "legal",
];

export default function OnboardingScreen() {
  const params = useLocalSearchParams<{ ref?: string }>();
  const { profile, refreshProfile, session } = useSessionContext();
  const [role, setRole] = useState<"job_seeker" | "employer">(
    profile?.role ?? "job_seeker",
  );
  const [fullName, setFullName] = useState(profile?.full_name ?? "");
  const [headline, setHeadline] = useState(profile?.headline ?? "");
  const [schoolName, setSchoolName] = useState(profile?.job_seeker_profiles?.school_name ?? "");
  const [jobFunction, setJobFunction] = useState<JobFunction | null>(
    profile?.job_seeker_profiles?.job_function ?? "engineering",
  );
  const [employersText, setEmployersText] = useState("");
  const [companyName, setCompanyName] = useState(profile?.employer_profiles?.company_name ?? "");
  const [companyDomain, setCompanyDomain] = useState(
    profile?.employer_profiles?.company_domain ?? "",
  );
  const [positionTitle, setPositionTitle] = useState(
    profile?.employer_profiles?.position_title ?? "",
  );
  const [resumePath, setResumePath] = useState<string | null>(null);
  const [videoPath, setVideoPath] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const employers = useMemo(
    () =>
      employersText
        .split(",")
        .map((value) => value.trim())
        .filter(Boolean),
    [employersText],
  );

  const pickResume = async () => {
    const result = await DocumentPicker.getDocumentAsync({
      copyToCacheDirectory: true,
      multiple: false,
      type: [
        "application/pdf",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "text/plain",
      ],
    });

    if (result.canceled) {
      return;
    }

    const file = result.assets[0];
    const upload = await uploadFileToBucket({
      bucket: "resumes",
      fileUri: file.uri,
      contentType: file.mimeType,
      path: `${session?.user.id}/${Date.now()}-${file.name}`,
    });

    setResumePath(upload.path);
  };

  const pickVideo = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Videos,
      quality: 1,
    });

    if (result.canceled) {
      return;
    }

    const asset = result.assets[0];
    const upload = await uploadFileToBucket({
      bucket: "videos",
      fileUri: asset.uri,
      contentType: asset.mimeType,
      path: `${session?.user.id}/${Date.now()}-intro.mov`,
    });

    setVideoPath(upload.publicUrl);
  };

  const handleSave = async () => {
    if (!session?.user.id) {
      return;
    }

    try {
      setSaving(true);

      const { error: profileError } = await supabase.from("profiles").upsert({
        id: session.user.id,
        role,
        full_name: fullName,
        headline,
        email: session.user.email,
        onboarding_complete: true,
      });

      if (profileError) {
        throw profileError;
      }

      if (role === "job_seeker") {
        const { error: seekerError } = await supabase
          .from("job_seeker_profiles")
          .upsert({
            profile_id: session.user.id,
            school_name: schoolName,
            job_function: jobFunction,
            intro_video_url: videoPath,
          });

        if (seekerError) {
          throw seekerError;
        }

        if (videoPath) {
          const { error: videoError } = await supabase
            .from("candidate_videos")
            .insert({
              profile_id: session.user.id,
              video_url: videoPath,
            });

          if (videoError) {
            throw videoError;
          }
        }

        await supabase.from("job_seeker_employers").delete().eq("profile_id", session.user.id);

        if (employers.length) {
          const { error: employersError } = await supabase
            .from("job_seeker_employers")
            .insert(
              employers.map((employerName, index) => ({
                profile_id: session.user.id,
                employer_name: employerName,
                sort_order: index + 1,
              })),
            );

          if (employersError) {
            throw employersError;
          }
        }

        if (resumePath) {
          const { data: resumeRow, error: resumeError } = await supabase
            .from("resume_uploads")
            .insert({
              profile_id: session.user.id,
              file_path: resumePath,
            })
            .select("id")
            .single();

          if (resumeError) {
            throw resumeError;
          }

          await invokeEdgeFunction("parse-resume", {
            resumeId: resumeRow.id,
          });
        }

        if (params.ref) {
          await invokeEdgeFunction("consume-referral-invite", {
            token: params.ref,
          });
        }
      }

      if (role === "employer") {
        const { error: employerError } = await supabase
          .from("employer_profiles")
          .upsert({
            profile_id: session.user.id,
            company_name: companyName,
            company_domain: companyDomain,
            position_title: positionTitle,
          });

        if (employerError) {
          throw employerError;
        }
      }

      await refreshProfile();
      router.replace(role === "employer" ? "/feed" : "/profile");
    } catch (error) {
      Alert.alert("Unable to save onboarding", error instanceof Error ? error.message : "Unknown error");
    } finally {
      setSaving(false);
    }
  };

  return (
    <Screen
      title="Finish your profile"
      subtitle="Every account chooses a role first, then the app routes into the right product experience."
    >
      <View style={styles.card}>
        <Text style={styles.label}>Role</Text>
        <View style={styles.toggleRow}>
          {(["job_seeker", "employer"] as const).map((value) => (
            <Pressable
              key={value}
              onPress={() => setRole(value)}
              style={[styles.modeButton, role === value && styles.modeButtonActive]}
            >
              <Text style={styles.modeLabel}>
                {value === "job_seeker" ? "Job seeker" : "Employer"}
              </Text>
            </Pressable>
          ))}
        </View>

        <Text style={styles.label}>Full name</Text>
        <TextInput
          onChangeText={setFullName}
          placeholder="Your name"
          placeholderTextColor={theme.colors.textMuted}
          style={styles.input}
          value={fullName}
        />

        <Text style={styles.label}>Headline</Text>
        <TextInput
          onChangeText={setHeadline}
          placeholder="Staff product designer | AI onboarding lead"
          placeholderTextColor={theme.colors.textMuted}
          style={styles.input}
          value={headline}
        />

        {role === "job_seeker" ? (
          <>
            <Text style={styles.label}>School</Text>
            <TextInput
              onChangeText={setSchoolName}
              placeholder="Stanford University"
              placeholderTextColor={theme.colors.textMuted}
              style={styles.input}
              value={schoolName}
            />

            <Text style={styles.label}>Previous employers</Text>
            <TextInput
              onChangeText={setEmployersText}
              placeholder="Stripe, Figma, Ramp"
              placeholderTextColor={theme.colors.textMuted}
              style={styles.input}
              value={employersText}
            />

            <Text style={styles.label}>Job function</Text>
            <View style={styles.chipWrap}>
              {jobFunctions.map((value) => (
                <Pressable
                  key={value}
                  onPress={() => setJobFunction(value)}
                  style={[
                    styles.chip,
                    jobFunction === value && styles.chipActive,
                  ]}
                >
                  <Text style={styles.chipLabel}>{value}</Text>
                </Pressable>
              ))}
            </View>

            <Pressable onPress={pickResume} style={styles.secondaryButton}>
              <Text style={styles.secondaryButtonText}>
                {resumePath ? "Resume uploaded" : "Upload resume"}
              </Text>
            </Pressable>

            <Pressable onPress={pickVideo} style={styles.secondaryButton}>
              <Text style={styles.secondaryButtonText}>
                {videoPath ? "Intro video uploaded" : "Upload 2-minute intro video"}
              </Text>
            </Pressable>
          </>
        ) : (
          <>
            <Text style={styles.label}>Company name</Text>
            <TextInput
              onChangeText={setCompanyName}
              placeholder="Acme"
              placeholderTextColor={theme.colors.textMuted}
              style={styles.input}
              value={companyName}
            />

            <Text style={styles.label}>Company domain</Text>
            <TextInput
              autoCapitalize="none"
              onChangeText={setCompanyDomain}
              placeholder="acme.com"
              placeholderTextColor={theme.colors.textMuted}
              style={styles.input}
              value={companyDomain}
            />

            <Text style={styles.label}>Role title</Text>
            <TextInput
              onChangeText={setPositionTitle}
              placeholder="Head of Product"
              placeholderTextColor={theme.colors.textMuted}
              style={styles.input}
              value={positionTitle}
            />
          </>
        )}

        <Pressable disabled={saving} onPress={handleSave} style={styles.primaryButton}>
          <Text style={styles.primaryButtonText}>Save and continue</Text>
        </Pressable>
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: theme.colors.card,
    borderRadius: theme.radius.lg,
    padding: theme.spacing.lg,
    gap: theme.spacing.sm,
    borderWidth: 1,
    borderColor: theme.colors.border,
  },
  label: {
    color: theme.colors.text,
    fontSize: 15,
    fontWeight: "600",
    marginTop: 8,
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
  toggleRow: {
    flexDirection: "row",
    gap: theme.spacing.sm,
  },
  modeButton: {
    flex: 1,
    alignItems: "center",
    backgroundColor: theme.colors.surface,
    borderRadius: theme.radius.sm,
    paddingVertical: 12,
  },
  modeButtonActive: {
    backgroundColor: theme.colors.primary,
  },
  modeLabel: {
    color: theme.colors.text,
    fontWeight: "600",
  },
  chipWrap: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: theme.spacing.sm,
  },
  chip: {
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderRadius: 999,
    backgroundColor: theme.colors.surface,
    borderWidth: 1,
    borderColor: theme.colors.border,
  },
  chipActive: {
    backgroundColor: theme.colors.accent,
    borderColor: theme.colors.accent,
  },
  chipLabel: {
    color: theme.colors.text,
    textTransform: "capitalize",
    fontWeight: "600",
  },
  primaryButton: {
    marginTop: theme.spacing.md,
    backgroundColor: theme.colors.primary,
    borderRadius: theme.radius.sm,
    paddingVertical: 16,
    alignItems: "center",
  },
  primaryButtonText: {
    color: "#2c1200",
    fontWeight: "700",
    fontSize: 16,
  },
  secondaryButton: {
    paddingVertical: 14,
    alignItems: "center",
    borderRadius: theme.radius.sm,
    backgroundColor: theme.colors.surface,
    borderWidth: 1,
    borderColor: theme.colors.border,
    marginTop: 6,
  },
  secondaryButtonText: {
    color: theme.colors.text,
    fontWeight: "600",
  },
});
