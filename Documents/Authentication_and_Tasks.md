# Authentication & Tasks, explained

This doc covers how sign-in and the task/reward system actually work now that they're backed
by real Firebase (Auth + Firestore), replacing the old in-memory mock described in
`Flutter.md`. Read this alongside `Flutter.md` for the general app structure - this one goes
deep on `AuthService`, `DatabaseService`, and the Firestore data behind them.

## The short version

- **Firebase Auth** handles "who are you" — email/password accounts, session tokens.
- **Firestore** handles "what do you see" — each user's profile, their household, and that
  household's tasks and rewards, all live-synced across every family member's device.
- A **household** is the unit everything else hangs off. Parents create one when they sign up;
  kids join an existing one with an **invite code**.

## Data model (Firestore)

```
users/{uid}                          — one doc per account: name, email, role, xp, householdId
households/{householdId}             — name, inviteCode, memberIds: [uid, uid, ...]
households/{householdId}/tasks/{id}      — title, assignedToUserId, rewardXp, status, ...
households/{householdId}/rewards/{id}    — title, type, xpCost, ...
```

Key thing to notice: **tasks and rewards are subcollections of a household**, not top-level
collections. Every family's data lives under their own `households/{householdId}` document,
which is what makes the household-scoped security rules (`firestore.rules`) simple — "can this
user read/write this doc?" almost always reduces to "is their uid in this household's
`memberIds`?"

`users/{uid}` is keyed by the **Firebase Auth uid**, not some app-generated id. That's the
thread that ties an Auth account to its Firestore profile — `AuthService` always looks up
`users/<FirebaseAuth uid>` to load the rest of what it needs (name, role, xp, which household).

## Authentication (`lib/core/services/auth_service.dart`)

`AuthService` wraps `FirebaseAuth.instance` and `FirebaseFirestore.instance`. It exposes the
same shape it always did (`login`, `register`, `logout`, `currentUser`, `isLoggedIn`) so the
rest of the app didn't need to change — only what happens *inside* those methods did.

### Registering — two different paths depending on role

**Parent:**
1. `FirebaseAuth.createUserWithEmailAndPassword(...)` — creates the account.
2. A new `households/{id}` doc is created, named `"<name>'s Family"`, with a random 6-character
   invite code (`_generateUniqueInviteCode`) and `memberIds: [uid]`.
3. `Reward.defaultCatalog` (the starter rewards — 50 XP, game time, a day out, a treat) is
   copied into `households/{id}/rewards/` via a batch write, so every new family starts with
   something to work toward.
4. A `users/{uid}` doc is created with `role: 'parent'` and `householdId` pointing at the new
   household.

**Child:**
1. The **invite code is required** and looked up first (`households` where `inviteCode ==
   CODE`). This has to happen *after* the Firebase Auth account exists, not before — Firestore's
   security rules require `request.auth != null` to even run the query, and
   `createUserWithEmailAndPassword` signs the new account in immediately, which is what makes
   that query legal.
2. If the code doesn't match anything, registration fails with "Invalid invite code..." — see
   the rollback note below.
3. Otherwise the child's uid is added to that household's `memberIds` via
   `FieldValue.arrayUnion`, and their `users/{uid}` doc is created with
   `householdId` set to the *existing* household (never a new one).

**Rollback on failure:** if anything after account creation throws (bad invite code, a network
blip mid-write), `register()` deletes the just-created Firebase Auth account
(`cred.user?.delete()`) before rethrowing. Without this, a failed registration would leave a
"ghost" account with no profile and no household — able to sign in, but broken everywhere else.

### Logging in

`signInWithEmailAndPassword`, then fetch `users/{uid}` and build the `AppUser` from it. If the
Firestore doc is missing (shouldn't normally happen, but e.g. a manually-deleted profile), the
user is signed back out and login fails with a clear error rather than leaving the app in a
half-logged-in state.

### Staying logged in between app launches

`main.dart` calls `authService.tryRestoreSession()` **before** `runApp()`. If Firebase Auth
still has a signed-in user (it persists tokens on-device by default), this fetches their
profile and populates `AuthService.currentUser` up front — so `app.dart` can pick
`AppRoutes.home` vs `AppRoutes.login` as the *initial* route correctly, instead of always
starting at the login screen and bouncing to home a moment later.

### Error messages

Firebase throws `FirebaseAuthException` with cryptic codes (`wrong-password`,
`email-already-in-use`, ...). `AuthService._friendlyAuthError()` maps the common ones to
human-readable strings; `login`/`register` wrap those in a plain `Exception(message)`, and the
screens (`login_screen.dart`, `register_screen.dart`) catch it and show it in a `SnackBar` —
look for `.replaceFirst('Exception: ', '')` in those files, that's just stripping Dart's default
`Exception.toString()` prefix.

## Invite codes

An invite code is a random 6-character string (letters/digits, ambiguous characters like `0`/`O`
and `1`/`I` excluded on purpose so it's easy to read aloud or retype) stored on the household
doc. A parent finds theirs via **Family tab → Add Family Member** (`family_screen.dart`), which
just reads `db.household!.inviteCode` and shows it in a dialog. There's currently no way for a
*second parent* to join an existing household (only the child role prompts for a code) — that's
a known gap, not an oversight, if it comes up.

## Tasks & rewards (`lib/core/services/database_service.dart`)

`DatabaseService` used to hold hardcoded demo data. Now it holds **live Firestore listeners**,
bound to whichever household the signed-in user belongs to:

```dart
void bindHousehold(String? householdId) {
  // cancels old listeners, starts new ones on households/{id},
  // households/{id}/tasks, households/{id}/rewards, and
  // users where householdId == id
}
```

`bindHousehold` is called automatically — you should never need to call it yourself. It's wired
up in `app.dart` via a `ChangeNotifierProxyProvider<AuthService, DatabaseService>`: every time
`AuthService` changes (login, logout, profile loaded), the proxy re-runs
`db.bindHousehold(auth.currentUser?.householdId)`, which is a no-op if the household hasn't
actually changed. This is *why* logging out correctly clears the Family/Home tabs instead of
leaving stale data on screen: `currentUser` becomes `null`, so `bindHousehold(null)` fires and
wipes `household`/`familyMembers`/`tasks`/`availableRewards`.

Because everything is a live Firestore `.snapshots()` listener rather than a one-time fetch,
**any change any family member makes shows up on every other family member's device without a
refresh** — a parent assigning a task appears on the kid's phone in real time, and vice versa.

### Task lifecycle

```
pending  →  completed  →  approved
 (assigned,   (child tapped     (parent tapped
  untouched)   "Mark Complete")  "Approve Task")
```

- `addTask(TaskModel)` — writes a new doc into `households/{id}/tasks` (used from the "Assign
  Tasks" screen's "Add New Task" dialog). Firestore assigns the doc id; the `id` field on the
  `TaskModel` you pass in is discarded (`toFirestore()` never includes it).
- `completeTask(id)` — child-side, flips `status` to `completed`. Doesn't touch XP yet — that
  only happens on approval, so a kid can't grant themselves points by completing something a
  parent hasn't checked.
- `approveTask(id)` — parent-side, and the only one that's a **Firestore transaction**, because
  it touches two documents atomically: the task (status → `approved`) and the assigned child's
  `users/{uid}` doc (`xp` incremented by `rewardXp`). See the gotcha below if you're editing
  this method.

### Gotcha: Firestore transactions and read/write ordering

The Flutter `cloud_firestore` plugin enforces something the server-side transaction model
doesn't strictly require in the same way: **every `transaction.get()` must run before any
`transaction.set()/update()/delete()` in that transaction.** Interleaving them (get, write, get,
write) throws `Failed assertion: '_commands.isEmpty': Transactions require all reads to be
executed before all writes.` at runtime — it won't show up in `flutter analyze`, only when the
code actually runs. `approveTask` does both `get`s (task, then the assigned user) first, and
only issues its two `update`s after. If you add a third document to that transaction later, keep
the same shape: all reads, then all writes.

### Rewards

`households/{id}/rewards` is just a catalog — `availableRewards` on `DatabaseService`. There's
no "redeem" flow wired up yet (the reward-choosing screen's "Confirm Rewards" button is still a
placeholder `SnackBar`); the catalog exists so the child's task screen can show progress bars
toward each reward's `xpCost`.

## Where to look for what

| Question | File |
|---|---|
| How does login/register actually call Firebase? | `lib/core/services/auth_service.dart` |
| How does a screen get the current user? | `context.watch<AuthService>().currentUser` |
| How do tasks/rewards get fetched? | `lib/core/services/database_service.dart` |
| How does a screen get the household's tasks? | `context.watch<DatabaseService>().tasks` |
| What can a signed-in user actually read/write? | `firestore.rules` |
| Where's the invite-code field on sign-up? | `lib/features/auth/screens/register_screen.dart` |
| Where's the invite code shown to a parent? | `lib/features/household/screens/family_screen.dart` |

## Security rules (`firestore.rules`)

Rules of thumb baked into the rules file:

- A user can always read/write their **own** `users/{uid}` doc; a **parent can also update a
  child's doc in the same household** (needed for the XP grant in `approveTask`).
- Anyone signed in can **read** any `households/*` doc — this is what lets a brand-new account
  look itself up by invite code before it's officially a member of anything. Practical
  consequence: **invite codes aren't a secret from other signed-in app users**, just from
  strangers off the internet. Treat them like a family Wi-Fi password, not a bank PIN.
- A household's `tasks`/`rewards` subcollections are readable/writable only by uids listed in
  that household's `memberIds`.
- Nothing is deletable from the client (`allow delete: if false` everywhere) — there's no
  "delete my account" or "delete this household" flow yet, so this just prevents accidental data
  loss until one exists.

**These rules live in this repo but aren't automatically deployed.** Changing `firestore.rules`
doesn't affect the live app until someone runs `firebase deploy --only firestore:rules` (needs
the Firebase CLI logged into the project) or pastes the file into the Firebase console's Rules
tab.

## Testing note

`test/app_smoke_test.dart`'s widget tests are currently `skip: true`. They build the real
`FamotiveApp`, which now constructs an `AuthService` that talks to `FirebaseAuth.instance` —
and that throws immediately in a plain `flutter test` run because there's no Firebase app
initialized (no platform channels in a widget test environment). Both `AuthService` and
`DatabaseService` accept optional constructor parameters
(`AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})`) specifically so that, if
someone wants to un-skip these later, they can inject fakes (e.g. the `firebase_auth_mocks` /
`fake_cloud_firestore` packages) instead of hitting the real backend.
