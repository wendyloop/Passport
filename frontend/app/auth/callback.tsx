import { ActivityIndicator, View } from "react-native";

import { theme } from "@/styles/theme";

export default function AuthCallbackScreen() {
  return (
    <View
      style={{
        flex: 1,
        alignItems: "center",
        justifyContent: "center",
        backgroundColor: theme.colors.background,
      }}
    >
      <ActivityIndicator color={theme.colors.primary} />
    </View>
  );
}
