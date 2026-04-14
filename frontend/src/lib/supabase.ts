import "react-native-url-polyfill/auto";

import AsyncStorage from "@react-native-async-storage/async-storage";
import * as QueryParams from "expo-auth-session/build/QueryParams";
import { makeRedirectUri } from "expo-auth-session";
import Constants from "expo-constants";
import * as WebBrowser from "expo-web-browser";
import { createClient } from "@supabase/supabase-js";

const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error("Missing Supabase environment variables for the frontend app.");
}

WebBrowser.maybeCompleteAuthSession();

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    storage: AsyncStorage,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
  },
});

export async function signInWithGoogle() {
  const redirectTo = makeRedirectUri({
    scheme: Constants.expoConfig?.scheme ?? "passport",
    path: "auth/callback",
  });

  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: "google",
    options: {
      redirectTo,
      skipBrowserRedirect: true,
      scopes: [
        "openid",
        "email",
        "profile",
        "https://www.googleapis.com/auth/calendar",
      ].join(" "),
    },
  });

  if (error) {
    throw error;
  }

  if (!data?.url) {
    throw new Error("Supabase did not return an OAuth URL.");
  }

  const result = await WebBrowser.openAuthSessionAsync(data.url, redirectTo);
  if (result.type !== "success") {
    return;
  }

  const { params, errorCode } = QueryParams.getQueryParams(result.url);
  if (errorCode) {
    throw new Error(errorCode);
  }

  const accessToken = params.access_token;
  const refreshToken = params.refresh_token;

  if (!accessToken || !refreshToken) {
    throw new Error("Google OAuth completed without a Supabase session.");
  }

  const { error: sessionError } = await supabase.auth.setSession({
    access_token: accessToken,
    refresh_token: refreshToken,
  });

  if (sessionError) {
    throw sessionError;
  }
}

export async function invokeEdgeFunction<TPayload extends object>(
  name: string,
  payload: TPayload,
) {
  const { data, error } = await supabase.functions.invoke(name, {
    body: payload,
  });

  if (error) {
    throw error;
  }

  return data;
}
