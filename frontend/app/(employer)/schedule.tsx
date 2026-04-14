import { useEffect, useState } from "react";
import {
  Alert,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";

import { Screen } from "@/components/screen";
import { supabase } from "@/lib/supabase";
import { useSessionContext } from "@/providers/session-provider";
import { theme } from "@/styles/theme";

type AvailabilitySlotRow = {
  id: string;
  start_at: string;
  end_at: string;
  slot_status: string;
};

type ApprovalRow = {
  id: string;
  status: string;
  candidate_profile_id: string;
};

export default function EmployerScheduleScreen() {
  const { profile } = useSessionContext();
  const [slots, setSlots] = useState<AvailabilitySlotRow[]>([]);
  const [requests, setRequests] = useState<ApprovalRow[]>([]);
  const [startAt, setStartAt] = useState("");
  const [endAt, setEndAt] = useState("");

  const loadData = async () => {
    const userId = profile?.id;
    if (!userId) {
      return;
    }

    const { data: slotRows, error: slotsError } = await supabase
      .from("availability_slots")
      .select("id, start_at, end_at, slot_status")
      .order("start_at", { ascending: true });

    if (slotsError) {
      Alert.alert("Unable to load schedule", slotsError.message);
      return;
    }

    const { data: approvalRows, error: approvalsError } = await supabase
      .from("interview_requests")
      .select("id, status, candidate_profile_id")
      .eq("status", "pending_employer_approval")
      .order("candidate_selected_at", { ascending: false });

    if (approvalsError) {
      Alert.alert("Unable to load approvals", approvalsError.message);
      return;
    }

    setSlots(slotRows ?? []);
    setRequests(approvalRows ?? []);
  };

  useEffect(() => {
    loadData();
  }, [profile?.id]);

  const addSlot = async () => {
    const { error } = await supabase.from("availability_slots").insert({
      employer_profile_id: profile?.id,
      start_at: new Date(startAt).toISOString(),
      end_at: new Date(endAt).toISOString(),
      source: "manual",
    });

    if (error) {
      Alert.alert("Unable to add slot", error.message);
      return;
    }

    setStartAt("");
    setEndAt("");
    await loadData();
  };

  const approveRequest = async (requestId: string, approved: boolean) => {
    const { error } = await supabase.functions.invoke("approve-interview", {
      body: {
        requestId,
        approved,
      },
    });

    if (error) {
      Alert.alert("Unable to update interview request", error.message);
      return;
    }

    await loadData();
  };

  const issueReferral = async () => {
    const { data, error } = await supabase.functions.invoke("create-referral-invite", {
      body: {},
    });

    if (error) {
      Alert.alert("Unable to create referral", error.message);
      return;
    }

    Alert.alert("Referral created", `Invite token: ${data.token}`);
  };

  return (
    <Screen
      title="Schedule"
      subtitle="Publish openings, approve reserved interview slots, and issue employer referrals."
    >
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Availability</Text>
        <TextInput
          onChangeText={setStartAt}
          placeholder="Start ISO time, e.g. 2026-05-01T15:00:00Z"
          placeholderTextColor={theme.colors.textMuted}
          style={styles.input}
          value={startAt}
        />
        <TextInput
          onChangeText={setEndAt}
          placeholder="End ISO time, e.g. 2026-05-01T15:30:00Z"
          placeholderTextColor={theme.colors.textMuted}
          style={styles.input}
          value={endAt}
        />
        <Pressable onPress={addSlot} style={styles.primaryButton}>
          <Text style={styles.primaryButtonText}>Add time slot</Text>
        </Pressable>
        <Pressable onPress={issueReferral} style={styles.secondaryButton}>
          <Text style={styles.secondaryButtonText}>Issue referral invite</Text>
        </Pressable>
      </View>

      {slots.map((slot) => (
        <View key={slot.id} style={styles.slotCard}>
          <Text style={styles.slotTitle}>{new Date(slot.start_at).toLocaleString()}</Text>
          <Text style={styles.slotBody}>
            {new Date(slot.end_at).toLocaleTimeString()} • {slot.slot_status}
          </Text>
        </View>
      ))}

      {requests.map((request) => (
        <View key={request.id} style={styles.requestCard}>
          <Text style={styles.cardTitle}>Pending approval</Text>
          <Text style={styles.slotBody}>Candidate: {request.candidate_profile_id}</Text>
          <View style={styles.row}>
            <Pressable
              onPress={() => approveRequest(request.id, true)}
              style={styles.primaryButton}
            >
              <Text style={styles.primaryButtonText}>Approve</Text>
            </Pressable>
            <Pressable
              onPress={() => approveRequest(request.id, false)}
              style={styles.rejectButton}
            >
              <Text style={styles.rejectButtonText}>Decline</Text>
            </Pressable>
          </View>
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
    gap: theme.spacing.sm,
    borderWidth: 1,
    borderColor: theme.colors.border,
  },
  cardTitle: {
    color: theme.colors.text,
    fontSize: 18,
    fontWeight: "700",
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
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: theme.colors.primary,
    paddingVertical: 14,
    borderRadius: theme.radius.sm,
  },
  primaryButtonText: {
    color: "#2c1200",
    fontWeight: "700",
  },
  secondaryButton: {
    alignItems: "center",
    justifyContent: "center",
    borderWidth: 1,
    borderColor: theme.colors.border,
    paddingVertical: 14,
    borderRadius: theme.radius.sm,
  },
  secondaryButtonText: {
    color: theme.colors.text,
    fontWeight: "600",
  },
  slotCard: {
    backgroundColor: theme.colors.surface,
    borderRadius: theme.radius.md,
    padding: theme.spacing.md,
    gap: 4,
  },
  slotTitle: {
    color: theme.colors.text,
    fontWeight: "700",
  },
  slotBody: {
    color: theme.colors.textMuted,
  },
  requestCard: {
    backgroundColor: theme.colors.card,
    borderRadius: theme.radius.lg,
    padding: theme.spacing.lg,
    gap: theme.spacing.sm,
    borderWidth: 1,
    borderColor: theme.colors.border,
  },
  row: {
    flexDirection: "row",
    gap: theme.spacing.sm,
  },
  rejectButton: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: theme.colors.danger,
    paddingVertical: 14,
    borderRadius: theme.radius.sm,
  },
  rejectButtonText: {
    color: "#fff5f7",
    fontWeight: "700",
  },
});
