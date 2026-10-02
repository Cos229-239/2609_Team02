# Famotive Cloud Functions — push notifications & repeating tasks

Sends Firebase Cloud Messaging (FCM) push notifications when household data
changes in Firestore, and turns repeating tasks into one task per day they
occur.

| Recipient | Event | Trigger | Tap opens |
|---|---|---|---|
| Children | New task in the shared pool | task created, unassigned | Tasks tab |
| Child | Task assigned to them | task created assigned, or a parent (re)assigns it | Task detail |
| Child | Morning digest: due today, overdue from yesterday, up for grabs | 9 AM household time | Task detail (single item) or Tasks tab |
| Child | Task approved | status `completed` → `approved` | Task detail |
| Parents | Child accepted a task | child claims a pool task | Task detail |
| Parents | Child completed a task | status → `completed` | Task detail |
| Parents | Child redeemed a reward | redemption created | Family tab |

Nobody is notified about their own action. Users who switch off
**Settings → Notifications → Push Notifications** (`users/{uid}.pushNotificationsEnabled == false`) get nothing.

## Household mornings (9 AM, family time)

Each household stores its IANA `timezone` (set by the app from the device
when the household is created, or backfilled the next time a member opens
the app). `onHouseholdWritten` turns that into `nextRunAt` — the next 9 AM
there. `runHouseholdMornings` runs every 30 minutes but only reads households
whose `nextRunAt` has passed (an indexed query, normally empty), so there's no
task scanning. For each one it:

1. advances `nextRunAt` to the next 9 AM (in a transaction — overlapping runs can't double-send),
2. creates repeating-task occurrences through **tomorrow**,
3. archives occurrences that were missed (still pending, due before yesterday; marked `missed: true`),
4. sends each child **one** notification: a single due/overdue/up-for-grabs task by name, or a
   "Today's quests" digest if there are several.

Change `MORNING_HOUR` in `src/notifications/recurrence.ts` to move it.

## Repeating tasks

Parents save a rule at `households/{id}/taskSchedules/{id}`:

| Field | Meaning |
|---|---|
| `repeat` | `daily`, `everyOtherDay`, `weekly`, `everyOtherWeek`, `monthly` |
| `weekdays` | ISO weekdays (1 = Mon … 7 = Sun) for `weekly` / `everyOtherWeek` |
| `startDate` | `YYYY-MM-DD`, household-local; every-other-day/week count from here, monthly uses its day of month (clamped to short months) |
| `assignedToUserId` | child, or null for the shared pool |
| `generatedThrough` | server bookkeeping: last day already handed out |

Each occurrence is an ordinary task (`{scheduleId}_{YYYYMMDD}`, with
`scheduleId`, `repeat`, `occurrenceDate`, and `dueDate` = local midnight), so
it's claimed, completed and approved on its own. They're created a day ahead
and the app hides them until their day. Creating a schedule generates
today's/tomorrow's right away (`onTaskScheduleWritten`); editing or deleting
one removes not-yet-started occurrences after today and regenerates.
Generated occurrences don't send the "new quest" push — the morning digest
covers them.

## Households & membership

- Membership is `households/{id}.memberIds`; a user can be in several households, and `users/{uid}.householdId` is only the one they're viewing. Recipients are always resolved from the household's `memberIds`, so a child in two households hears about tasks from both.
- `notifyOnJoinRequested`: someone entered the invite code (`households/{id}/joinRequests/{uid}`) → push to the household admin (`ownerId`) only.
- `notifyOnMembersAdded`: someone was added to `memberIds` (admin approved them, or a parent created a child account) → "You're in!" to the new member.

## Data retention

The morning run deletes the household's tasks whose `createdAt` is more than 60 days old (`TASK_RETENTION_DAYS`, kept in sync with `AppConstants.taskDeleteAfterDays`). The app also hides them and a parent's device sweeps them.

## Account deletion (`deleteAccount` callable)

In-app **Settings → Account Settings → Delete Account**, and **Family → ⋮ → Delete account** on a child (admin only). The app calls it once with `dryRun: true` to show what will happen, re-authenticates the user, then calls it for real. Rules (`src/account/plan.ts`, unit tested):

- Admin of a household that has another parent → blocked until they make someone else admin.
- Admin and only parent → that household is deleted (`recursiveDelete`: tasks, schedules, rewards, redemptions, join requests), plus child accounts they created that aren't in any other household.
- Any other household → just removed from `memberIds`; for a child, their tasks, redemptions and repeating tasks there are deleted too.
- Then `users/{uid}` (with `fcmTokens`), open join requests and the Firebase Auth user are deleted.
- Deleting someone else: only a child, only by the admin of every household that child is in.
- Real runs require a sign-in less than 5 minutes old (`auth_time`).

Deploy with `firebase deploy --only functions:deleteAccount`.

If the app gets `UNAUTHENTICATED`, the function's Cloud Run service isn't publicly invokable (the code sets `invoker: 'public'`, but a deploy can fail to apply it). Fix: Google Cloud console → Cloud Run → `deleteaccount` → Security → *Allow public access*, or
`gcloud run services add-iam-policy-binding deleteaccount --region=us-central1 --member=allUsers --role=roles/run.invoker --project=famotive-8c858`.
Firebase Auth is still enforced inside the function.

## Layout

- `src/index.ts` — Firestore triggers, the household morning run, occurrence generation, FCM sending and dead-token cleanup.
- `src/notifications/plan.ts` — pure "who gets what" rules (unit tested).
- `src/notifications/recurrence.ts` — time zones and repeat rules (unit tested).
- `src/notifications/messages.ts` — notification copy.
- Device tokens: `users/{uid}/fcmTokens/{token}`, written by `lib/core/services/notification_service.dart`.

## One-time setup

1. **Blaze plan.** Cloud Functions (and Cloud Scheduler for the morning run) require the Firebase project to be on the pay-as-you-go plan. Usage at family scale stays well inside the free tier.
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

Deploy rules too: they add the `fcmTokens` and `taskSchedules` subcollections.
All queries use Firestore's automatic single-field indexes.

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
8. Create a task due today for the child → at 9 AM household time (within 30 minutes) the child gets "Quest due today". To test without waiting, set the household's `nextRunAt` to a past time in the console.
9. Create a repeating task (e.g. weekly, Mon & Thu) → its occurrences appear on those days; edit it → future ones update.
10. With the app open, notifications appear as an in-app banner with a **View** button.
11. Log out on device B → no further notifications arrive there.
