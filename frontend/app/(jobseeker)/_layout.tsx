import { Tabs } from "expo-router";
import { Ionicons } from "@expo/vector-icons";

import { theme } from "@/styles/theme";

export default function JobSeekerLayout() {
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: theme.colors.primary,
        tabBarInactiveTintColor: theme.colors.textMuted,
        tabBarStyle: {
          backgroundColor: theme.colors.card,
          borderTopColor: theme.colors.border,
        },
      }}
    >
      <Tabs.Screen
        name="profile"
        options={{
          title: "Profile",
          tabBarIcon: ({ color, size }) => (
            <Ionicons color={color} name="person-circle-outline" size={size} />
          ),
        }}
      />
      <Tabs.Screen
        name="interviews"
        options={{
          title: "Requests",
          tabBarIcon: ({ color, size }) => (
            <Ionicons color={color} name="calendar-outline" size={size} />
          ),
        }}
      />
    </Tabs>
  );
}
