# Social Sign-In Setup (Google & Apple)

How "Continue with Google" and "Continue with Apple" work in Famotive, and
what has to be configured outside the code for them to work.

## How it works

| | Google | Apple |
| --- | --- | --- |
| Platforms | Android + iOS | iOS only (`SocialSignInButtons.appleAvailable`) |
| Client package | `google_sign_in` (native account picker) | none: `firebase_auth`'s `AppleAuthProvider` |
| Firebase credential | `GoogleAuthProvider.credential(idToken:)` | `signInWithProvider(AppleAuthProvider())` |

Code: `lib/core/services/auth_service.dart` (`signInWithGoogle`,
`signInWithApple`, `completeSocialSignUp`, `cancelSocialSignUp`) and
`lib/features/auth/widgets/social_sign_in_buttons.dart`.

### Flow

1. The user taps a button on the Login or Register screen.
2. **Returning user** (a `users/{uid}` profile exists): signed straight in.
3. **New user** (Firebase Auth account but no profile):
   `FinishSignUpScreen` (`/finish-sign-up`) collects name, optional phone,
   role, and start/join household (the same rules as email sign-up), then
   `completeSocialSignUp` creates the profile.
4. **Backing out** of `FinishSignUpScreen` waits for `cancelSocialSignUp`,
   which deletes the half-made Auth account (only if it still has no
   profile) and signs out of Firebase and Google before the screen closes.

### Account deletion

Social accounts have no password, so before deletion the app
re-authenticates with the same provider (`reauthenticate…`). For Apple, the
authorization code from that re-auth is used to **revoke Apple's tokens**
(`revokeTokenWithAuthorizationCode`), which Apple requires when an account
is deleted.

## Configuration checklist

### Firebase console (project `famotive-8c858`)

- Authentication → Sign-in method: enable **Google** and **Apple**.
- Apple provider: fill in the Services ID, Apple Team ID, Key ID and
  private key (OAuth code flow). Firebase needs these to revoke Apple tokens
  on account deletion.

### Android

- Add the **SHA-1 and SHA-256** fingerprints of every signing key (debug,
  release, and Play App Signing) under Project settings → Android app, then
  re-download `android/app/google-services.json`. Without them, Google
  sign-in fails with `DEVELOPER_ERROR` / code 10.
- `AppConstants.googleServerClientId` must be the **web** OAuth client
  (`client_type: 3` in `google-services.json`); Android ID tokens are issued
  for it.

### iOS

- `AppConstants.googleIosClientId` = `CLIENT_ID` from
  `ios/Runner/GoogleService-Info.plist`.
- `ios/Runner/Info.plist` → `CFBundleURLTypes` must contain that plist's
  `REVERSED_CLIENT_ID` (the Google OAuth redirect). Update both if the plist
  is re-downloaded with a new client.
- Sign in with Apple: `ios/Runner/Runner.entitlements` has
  `com.apple.developer.applesignin`. Also enable **Sign in with Apple** under
  Xcode → Runner → Signing & Capabilities (and on the App ID in the Apple
  Developer portal) so the provisioning profile includes it.
- App Store guideline 4.8: an app offering Google sign-in on iOS must also
  offer Sign in with Apple, which is why Apple shows on iOS only.

## Testing

- `test/social_sign_in_test.dart` covers the Google path with an injected
  ID-token provider (`AuthService(googleIdTokenProvider: …)`), so no native
  picker is needed.
- Apple sign-in can only be tested on a real iOS device or simulator signed
  with a team that has the capability.
