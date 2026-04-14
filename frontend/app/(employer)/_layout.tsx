import { Tabs } from "expo-router";
import { Ionicons } from "@expo/vector-icons";

import { theme } from "@/styles/theme";

export default function EmployerLayout() {
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
        name="feed"
        options={{
          title: "Feed",
          tabBarIcon: ({ color, size }) => (
            <Ionicons color={color} name="play-circle-outline" size={size} />
          ),
        }}
      />
      <Tabs.Screen
        name="liked"
        options={{
          title: "Liked",
          tabBarIcon: ({ color, size }) => (
            <Ionicons color={color} name="heart-outline" size={size} />
          ),
        }}
      />
      <Tabs.Screen
        name="schedule"
        options={{
          title: "Schedule",
          tabBarIcon: ({ color, size }) => (
            <Ionicons color={color} name="calendar-clear-outline" size={size} />
          ),
        }}
      />
    </Tabs>
  );
}
