# Famotive

> **Together. Support. Grow.**

Famotive is a Flutter app for iOS and Android that turns household chores into quests. Parents create and assign tasks, kids complete them to earn XP and coins, parents approve the work, and kids spend their coins in a family reward store.

```text
Parent assigns → Child completes → Parent approves → Child earns XP + coins → Child redeems rewards
```

## Features

**For parents**

- Create a household on sign-up and invite kids with a household invite code
- Create, edit, reassign, archive and delete tasks — assigned to a child or left in a shared pool for any child to claim
- Pick a task icon and get an auto-suggested description; set XP and coin rewards, due dates and recurrence
- Review tasks grouped by status (pending, awaiting approval, approved) and approve completed work
- Manage the reward store (screen time, activities, treats, badges, …) and see redemptions
- Family and Progress tabs to track each child

**For kids**

- Simplified Home / Tasks / Rewards experience
- Claim tasks from the shared pool, mark tasks complete, and see what's awaiting approval
- Earn XP (level up every 500 XP) and coins; pin a reward to work toward and redeem it

**Account & app**

- Email/password auth with in-app password reset and email change via deep links (`famotive.org/__/auth/links`)
- Account settings, avatar picker, notification settings, Help & Support
- Push notifications (FCM) for new/assigned tasks, due-today and overdue reminders, completions, approvals and redemptions — see [functions/README.md](functions/README.md)

## Tech Stack

| Layer | Tools |
|---|---|
| App | Flutter / Dart (SDK ^3.13), Material, `provider` for state |
| Backend | Firebase Auth, Cloud Firestore (rules + indexes in repo), Firebase Cloud Messaging |
| Server | Cloud Functions for Firebase (TypeScript, Node 22) in `functions/` |
| Other | `app_links` (deep links), `url_launcher`, `intl` |
| Testing | `flutter_test`, `fake_cloud_firestore`, `firebase_auth_mocks`, `node --test` |

Firebase project: `famotive-8c858`.

## Getting Started

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) (includes Dart)
- Xcode (iOS) and/or Android Studio (Android)
- VS Code (recommended) and Git
- For backend work: Node 22 and the [Firebase CLI](https://firebase.google.com/docs/cli)

### Run the app

```bash
git clone <repository-url>
cd 2609_Team02
flutter pub get
flutter run
```

`lib/firebase_options.dart` is in the repo, but the native Firebase config files (`android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`) are gitignored. Generate them once per clone (needs access to the `famotive-8c858` Firebase project):

```bash
dart pub global activate flutterfire_cli
firebase login
flutterfire configure --project=famotive-8c858 --platforms=android,ios \
  --ios-bundle-id=com.famotive --android-package-name=com.famotive --yes
```

If that changes the app IDs in `lib/firebase_options.dart` or `firebase.json`, don't commit it — it registered new Firebase apps instead of using the existing ones. iOS dependencies are managed through Swift Package Manager (no CocoaPods).

### Run tests

```bash
flutter test                      # app unit/widget tests
cd functions && npm install && npm test   # Cloud Functions notification-planner unit tests
```

### Deploy backend

```bash
firebase deploy --only firestore:rules,firestore:indexes,functions
```

Push notifications need the Blaze plan and an APNs key for iOS — the one-time setup is in [functions/README.md](functions/README.md).

## Project Structure

```text
2609_Team02/
├── lib/
│   ├── main.dart
│   ├── firebase_options.dart
│   ├── app/                      # app.dart, routes.dart, theme.dart
│   ├── core/
│   │   ├── constants/            # app_constants.dart, task_icons.dart
│   │   ├── models/               # user, household, task, reward, redemption
│   │   ├── services/             # auth, database (Firestore), notification,
│   │   │                         # deep_link, description_suggester
│   │   └── utils/                # validators.dart
│   ├── features/
│   │   ├── auth/                 # login, register, forgot/reset password,
│   │   │                         # confirm email change
│   │   ├── household/            # parent home, family screen, member cards
│   │   ├── tasks/                # task list/detail/create/completion,
│   │   │                         # child home/tasks/rewards screens, task_tile
│   │   ├── rewards/              # progress screen, reward editor/progress tiles
│   │   └── profile/              # settings, account & notification settings,
│   │                             # avatar picker, password dialogs
│   └── shared/
│       ├── layouts/              # main_tab_shell.dart (role-based bottom nav)
│       ├── screens/              # route_not_found_screen.dart
│       └── widgets/              # app_button, app_card, loading_indicator,
│                                 # number_stepper
├── functions/                    # Cloud Functions (push notifications)
│   └── src/                      # index.ts, notifications/{plan,messages}.ts
├── test/                         # widget, model and database service tests
├── android/  ios/
├── Documents/                    # team onboarding guides (Flutter, Git, Trello)
├── firebase.json
├── firestore.rules
├── firestore.indexes.json
└── pubspec.yaml
```

## Development Workflow

Branch from `dev`:

```bash
git switch dev
git pull
git switch -c feature/<feature-name>
```

Commit, push, and open a pull request into `dev`:

```bash
git add .
git commit -m "Add <feature>"
git push -u origin feature/<feature-name>
```

Bug fixes should come with a regression test (see `test/` for examples).

## Docs

- [Documents/Flutter.md](Documents/Flutter.md) — Flutter onboarding for this codebase (layout, Provider, navigation, theming, recipes)
- [Documents/Authentication_and_Tasks.md](Documents/Authentication_and_Tasks.md)
- [Documents/GIT_01_Clone_and_Branch.md](Documents/GIT_01_Clone_and_Branch.md) and the other `GIT_*` guides
- [Documents/Trello_Walkthrough.md](Documents/Trello_Walkthrough.md)
- [functions/README.md](functions/README.md) — push notification setup, deploy and manual test checklist

## Team

Famotive is a team project developed as part of a Full Sail University course.

<table>
<tr>
<td width="160" align="center">

<img src="https://github.com/skidgfx.png" width="120" height="120" style="border-radius: 50%;">

</td>
<td>

# Nathan Pillman
### `SOFTWARE ENGINEER // SYSTEMS`

> **CALLSIGN:** @SKIDGFX  
> **STATUS:** `ONLINE`  
> **SPECIALIZATION:** FULL-STACK / C++ / DART  

</td>
</tr>
<tr>
<td width="160" align="center">

<img src="https://github.com/babyrhedd.png" width="120" height="120" style="border-radius: 50%;">

</td>
<td>

# Ashley Campbell
### `SOFTWARE ENGINEER // UI`

> **CALLSIGN:** @babyrhedd  
> **STATUS:** `ONLINE`  
> **SPECIALIZATION:** FRONT-END / C++  

</td>
</tr>
<tr>
<td width="160" align="center">

<img src="https://github.com/TKLoum.png" width="120" height="120" style="border-radius: 50%;">

</td>
<td>

# Tiffany Loum
### `SOFTWARE ENGINEER // QA`

> **CALLSIGN:** @TKLoum
> **STATUS:** `ONLINE`  
> **SPECIALIZATION:**  QA / INTEGRATION / TEST AUTOMATION

</td>
</tr>
</table>

