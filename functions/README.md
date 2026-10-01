# Famotive Cloud Functions — push notifications

Sends Firebase Cloud Messaging (FCM) push notifications when household data
changes in Firestore.

| Recipient | Event | Trigger | Tap opens |
|---|---|---|---|
| Children | New task in the shared pool | task created, unassigned | Tasks tab |
| Child | Task assigned to them | task created assigned, or a parent (re)assigns it | Task detail |
| Child | Task due today | scheduled sweep, 3 PM on the due day | Task detail |
| Child | Task past due | scheduled sweep, 8 AM the day after | Task detail |
| Child | Task approved | status `completed` → `approved` | Task detail |
| Parents | Child accepted a task | child claims a pool task | Task detail |
| Parents | Child completed a task | status → `completed` | Task detail |
| Parents | Child redeemed a reward | redemption created | Family tab |

Nobody is notified about their own action. Users who switch off
**Settings → Notifications → Push Notifications** (`users/{uid}.pushNotificationsEnabled == false`) get nothing.

Due times are relative to the task's `dueDate`, which the app stores as local
midnight of the due day, so "3 PM" / "8 AM" are in the family's own time zone.
Change `DUE_REMINDER_OFFSET_MS` / `OVERDUE_OFFSET_MS` in
`src/notifications/plan.ts` to adjust. Each reminder is sent once per due
date (`notificationLog` on the task doc); moving the due date re-arms it.

## Layout

- `src/index.ts` — Firestore triggers, the 15‑minute scheduled sweep, FCM sending and dead-token cleanup.
- `src/notifications/plan.ts` — pure "who gets what" rules (unit tested).
- `src/notifications/messages.ts` — notification copy.
- Device tokens: `users/{uid}/fcmTokens/{token}`, written by `lib/core/services/notification_service.dart`.

## One-time setup

1. **Blaze plan.** Cloud Functions (and Cloud Scheduler for the due-date sweep) require the Firebase project to be on the pay-as-you-go plan. Usage at family scale stays well inside the free tier.
2. **iOS / APNs.**
   - Apple Developer → Keys → create a key with *Apple Push Notifications service (APNs)*; download the `.p8`.
   - Firebase console → Project settings → Cloud Messaging → *Apple app configuration* → upload the key (Key ID + Team ID).
   - Xcode → Runner target → Signing & Capabilities → **+ Capability → Push Notifications** and **Background Modes → Remote notifications**. (`ios/Runner/Runner.entitlements` and `Info.plist` already contain the keys; adding the capabilities wires them into the target and provisioning profile.)
   - Push needs a real device or an Apple-silicon simulator (iOS 16+).
3. **Android.** Nothing extra once `google-services.json` has been generated (see the root README). Android 13+ shows a permission prompt on first sign-in.
4. **Firestore location.** Functions deploy to `us-central1` by default. If the Firestore database is in a different region, set `region` in `setGlobalOptions` in `src/index.ts` to match.

## Build, test, deploy

```bash
cd functions
npm install
npm test            # compiles + runs the unit tests for src/notifications (node --test)
                    # — these don't exercise firestore.rules; test those with the emulator

# from the repo root:
firebase deploy --only firestore:rules,firestore:indexes,functions
```

Deploy rules and indexes too: the rules add the `fcmTokens` subcollection,
and the sweep needs the collection-group index on `tasks.dueDate`.

Logs: `firebase functions:log` (or Google Cloud console → Logging).

Trigger events are de-duplicated with marker docs in `notificationEvents`
(admin-only). To purge old markers automatically, add a Firestore TTL policy
on the `expiresAt` field of the `notificationEvents` collection group
(Firestore → TTL in the console).

## Manual test

1. Sign in as a parent on device A and as a child on device B; allow notifications on both.
2. Parent creates an unassigned task → child gets "New quest available!".
3. Parent creates a task assigned to the child → child gets "New quest assigned".
4. Child claims a task from the pool → parent gets "<child> accepted a task".
5. Child marks a task complete → parent gets "<child> completed a task".
6. Parent approves → child gets "Quest approved!".
7. Child redeems a reward → parent gets "<child> redeemed a reward".
8. Set a task's due date to today (wait for 3 PM) or yesterday (wait for 8 AM) → child gets the due / overdue reminder within 15 minutes.
9. With the app open, notifications appear as an in-app banner with a **View** button.
10. Log out on device B → no further notifications arrive there.
