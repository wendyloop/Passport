import { useEffect, useState } from "react";
import { Alert, Pressable, StyleSheet, Text, View } from "react-native";

import { Screen } from "@/components/screen";
import { supabase } from "@/lib/supabase";
import { theme } from "@/styles/theme";

type InterviewRequestRow = {
  id: string;
  status: string;
  employer_profile_id: string;
  availability_slot_id: string | null;
};

type AvailabilitySlotRow = {
  id: string;
  employer_profile_id: string;
  start_at: string;
  end_at: string;
};

export default function JobSeekerInterviewsScreen() {
  const [requests, setRequests] = useState<InterviewRequestRow[]>([]);
  const [slots, setSlots] = useState<Record<string, AvailabilitySlotRow[]>>({});

  const loadData = async () => {
    const { data: requestRows, error: requestError } = await supabase
      .from("interview_requests")
      .select("id, status, employer_profile_id, availability_slot_id")
      .order("requested_at", { ascending: false });

    if (requestError) {
      Alert.alert("Unable to load interview requests", requestError.message);
      return;
    }

    setRequests(requestRows ?? []);

    const uniqueEmployerIds = [...new Set((requestRows ?? []).map((row) => row.employer_profile_id))];
    const groupedSlots: Record<string, AvailabilitySlotRow[]> = {};

    for (const employerId of uniqueEmployerIds) {
      const { data: slotRows, error: slotError } = await supabase
        .from("availability_slots")
        .select("id, employer_profile_id, start_at, end_at")
        .eq("employer_profile_id", employerId)
        .eq("slot_status", "open")
        .order("start_at", { ascending: true });

      if (slotError) {
        Alert.alert("Unable to load availability", slotError.message);
        return;
      }

      groupedSlots[employerId] = slotRows ?? [];
    }

    setSlots(groupedSlots);
  };

  useEffect(() => {
    loadData();
  }, []);

  const selectSlot = async (requestId: string, slotId: string) => {
    const { error } = await supabase.rpc("select_interview_slot", {
      p_request_id: requestId,
      p_slot_id: slotId,
    });

    if (error) {
      Alert.alert("Unable to reserve the slot", error.message);
      return;
    }

    await loadData();
  };

  return (
    <Screen
      title="Interview requests"
      subtitle="Any employer that likes your profile can send a request and let you choose from open time slots."
    >
      {requests.map((request) => (
        <View key={request.id} style={styles.card}>
          <Text style={styles.cardTitle}>Request status: {request.status}</Text>
          <Text style={styles.cardBody}>
            Employer availability opens here until you reserve one slot for approval.
          </Text>
          <View style={styles.slotWrap}>
            {(slots[request.employer_profile_id] ?? []).map((slot) => (
              <Pressable
                key={slot.id}
                onPress={() => selectSlot(request.id, slot.id)}
                style={styles.slot}
              >
                <Text style={styles.slotText}>
                  {new Date(slot.start_at).toLocaleString()} -{" "}
                  {new Date(slot.end_at).toLocaleTimeString()}
                </Text>
              </Pressable>
            ))}
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
    borderWidth: 1,
    borderColor: theme.colors.border,
    gap: theme.spacing.sm,
  },
  cardTitle: {
    color: theme.colors.text,
    fontWeight: "700",
    fontSize: 18,
  },
  cardBody: {
    color: theme.colors.textMuted,
    lineHeight: 20,
  },
  slotWrap: {
    gap: 10,
    marginTop: 8,
  },
  slot: {
    backgroundColor: theme.colors.surface,
    paddingHorizontal: 14,
    paddingVertical: 12,
    borderRadius: theme.radius.sm,
  },
  slotText: {
    color: theme.colors.text,
    fontWeight: "600",
  },
});
