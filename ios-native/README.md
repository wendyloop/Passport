# Passport Native iOS

This folder contains a standalone SwiftUI iOS app for Passport.

It is intentionally separate from the Expo app in `frontend/` so you can:

- keep `frontend/` for Android or cross-platform work
- open a native iOS project directly in Xcode
- iterate on iOS UI without Expo / CocoaPods / React Native build issues

## Open in Xcode

Open:

- `ios-native/PassportNative.xcodeproj`

Then choose the `PassportNative` scheme and run it on an iPhone simulator.

## Current state

- Native SwiftUI onboarding shell
- Employer feed / liked / schedule tabs
- Job seeker profile / interview requests tabs
- Mock data only for now
- No live Supabase integration yet

## Next steps for backend hookup

The cleanest path is:

1. keep Supabase as the shared backend
2. add a native Swift networking layer in this app
3. later add real auth, profile save/load, feed fetches, likes, and interview requests
