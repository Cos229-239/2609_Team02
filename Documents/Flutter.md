# Flutter, for teammates who've never used it

This doc explains how the Famotive app is put together, in Flutter/Dart terms, for anyone
coming from Kotlin/Jetpack Compose, web, or nothing at all. It's not a full Flutter course —
just enough to read the codebase, find where things live, and add a screen without guessing.

## The 60-second version

Flutter is Google's UI toolkit for building one codebase that compiles to iOS, Android, web
and desktop. You write **Dart** (a C-style, statically typed language — closer to Kotlin than
you'd expect) and describe your UI as a tree of **widgets**. If you know Jetpack Compose: a
Flutter widget is basically a `@Composable` function, except it's a class instead of a
function, and instead of `remember { }` you get a `StatefulWidget`. Same idea — describe the
UI as a function of state, and the framework re-renders when that state changes.

There's no XML layout file, no Storyboard, no separate "view" file. Everything — layout,
styling, behavior — is Dart code in `lib/`.

## Getting it running

Full setup (installing Flutter, SDKs, cloning) is in the main `README.md`. Once that's done,
the day-to-day loop is:

```bash
flutter pub get   # installs/updates dependencies (like `npm install` or Gradle sync)
flutter run       # builds and launches on whatever device/simulator is connected
```

While `flutter run` is active in a terminal:
- press **`r`** for **hot reload** — injects your code changes into the running app in about a
  second, keeping app state intact (you stay logged in, stay on the same screen). This is the
  single biggest thing that makes Flutter fast to work in — use it constantly.
- press **`R`** for **hot restart** — like hot reload but resets all state. Use this when hot
  reload doesn't seem to have picked up a change (usually because you changed something outside
  a `build()` method, like a top-level constant or `main()`).
- press **`q`** to quit.

## Project layout

```
lib/
├── main.dart              # entry point — just calls AppConfig.load() and runApp()
├── app/                   # app-wide wiring: theme, routes, the root widget
│   ├── app.dart
│   ├── routes.dart
│   └── theme.dart
├── core/                  # things every feature depends on
│   ├── config/            # environment config (dev/staging/prod)
│   ├── constants/         # shared spacing/sizing/copy constants
│   ├── models/            # plain data classes (AppUser, TaskModel, Reward, Household)
│   ├── services/          # app-wide state: AuthService, DatabaseService, ApiService
│   └── utils/              # form validators etc.
├── features/               # one folder per feature area, each self-contained
│   ├── auth/                # login, register
│   ├── household/           # "Home" + "Family" tabs
│   ├── tasks/                # task list/detail/create/completion
│   ├── rewards/              # progress tab, reward picker
│   └── profile/              # "Settings" tab
└── shared/                  # reusable, feature-agnostic building blocks
    ├── widgets/               # AppButton, AppCard, LoadingIndicator
    └── layouts/                # MainTabShell (the bottom-nav shell)
```

Each `features/<name>/` folder follows the same shape: `screens/` (full pages), `widgets/`
(smaller reusable pieces used only within that feature), and sometimes `services/` (feature-
specific business logic, e.g. `task_service.dart`). If you're adding a new "Family Challenges"
feature later, it gets its own `features/challenges/` folder with the same shape — that's the
convention to follow.

## The widget tree, in this app's terms

Two kinds of widgets show up everywhere in `lib/`:

- **`StatelessWidget`** — for anything that just renders based on the data it's given, e.g.
  `ProfileScreen`, `AppCard`, `AppButton`. No internal state of its own.
- **`StatefulWidget`** — for anything that needs to remember something between rebuilds, like
  form input as the user types (`LoginScreen`) or which tab is currently selected
  (`MainTabShell`). It comes with a matching `State` class that holds the mutable fields and a
  `setState(() { ... })` call to say "something changed, please rebuild."

Every widget's `build(BuildContext context)` method returns the widget tree for that piece of
UI. `BuildContext` is how a widget finds things above it in the tree — the current theme
(`Theme.of(context)`), the nearest `Navigator`, or (in this app) the shared app state via
`Provider` — see below.

## State management: Provider

Famotive uses the [`provider`](https://pub.dev/packages/provider) package rather than
`setState` for anything that needs to be shared across multiple screens — think of it as this
app's equivalent of a shared `ViewModel`. Two services are registered app-wide in
`app/app.dart`:

- **`AuthService`** — who's logged in.
- **`DatabaseService`** — the household's data: family members, tasks, rewards.

Both extend `ChangeNotifier`: they hold mutable state and call `notifyListeners()` whenever
that state changes. Any widget below the `MultiProvider` in `app.dart` can then read that state
two ways:

```dart
final db = context.watch<DatabaseService>();   // rebuild this widget whenever db changes
final auth = context.read<AuthService>();      // read it once, e.g. inside a button's onPressed
```

`watch` is what you'll see at the top of most screen `build()` methods — it's what makes the
UI update automatically the moment, say, a task gets marked complete. `read` is for one-off
calls that don't need to trigger a rebuild (you almost always use it inside callbacks like
`onPressed`, never inside `build()`).

**Both are backed by Firebase now** — `AuthService` by Firebase Auth, `DatabaseService` by live
Firestore listeners. See `Authentication_and_Tasks.md` for how sign-in, households, and the
task/reward lifecycle actually work under the hood. `ApiService` and
`core/config/app_config.dart` (environment + `API_BASE_URL`, set via `--dart-define`) remain
unused scaffolding for a future non-Firebase REST need.

## Navigation

All routing goes through one place: `app/routes.dart`. Routes are plain string constants
(`AppRoutes.home`, `AppRoutes.taskDetail`, ...) resolved by a single `onGenerateRoute`
function, rather than each screen wiring up its own `MaterialPageRoute`. To navigate:

```dart
Navigator.of(context).pushNamed(AppRoutes.taskCreate);              // push a new screen on top
Navigator.of(context).pushNamed(AppRoutes.taskList, arguments: id); // ...with data
Navigator.of(context).pop();                                        // go back
```

There's one deliberate exception worth knowing about: the 4 bottom-nav tabs (Home, Family,
Progress, Settings) do **not** each live on their own page/route. They're all children of a
single persistent `MainTabShell` (`shared/layouts/main_tab_shell.dart`), which owns one
`Scaffold` + `NavigationBar` for the whole signed-in session and swaps between tabs with a
local `setState` (an `IndexedStack` index), not a `Navigator` push. This matters because it's
the opposite of what you might expect from "each screen is a page" — it exists specifically so
switching tabs doesn't tear down and rebuild the nav bar (and lose scroll position) on every
tap. If you're adding a 5th tab, it goes into `MainTabShell`'s `_tabBodies` list and the
`AppTab` enum, not into `routes.dart` as a standalone page. Anything pushed *on top of* the
tabs (task detail, create task, choose reward, ...) is a normal named route with a back button,
same as any other screen.

## Theming

`app/theme.dart` defines `AppTheme.light` (a single `ThemeData`) and the brand colors in
`AppColors`. It's applied once, in `app/app.dart`'s `MaterialApp(theme: AppTheme.light, ...)`.
Individual widgets shouldn't hardcode colors/fonts — pull from `Theme.of(context)` (e.g.
`Theme.of(context).colorScheme.primary`, `Theme.of(context).textTheme.titleMedium`) so a future
rebrand only touches `theme.dart`.

## Adding things — quick recipes

**A new field on an existing screen:** just edit that screen's `build()` method. Most screens
in `features/*/screens/` are plain `StatelessWidget`s returning a `ListView`/`Column` of
widgets from `shared/widgets/` — copy the pattern already on the page.

**A new screen:** add it under the right `features/<area>/screens/` folder, add a route
constant + case in `app/routes.dart`, and navigate to it with `pushNamed`. If it's meant to
live behind the bottom nav (rare), it goes through `MainTabShell` instead — see above.

**A new reusable widget:** if it's only used within one feature, put it in that feature's
`widgets/` folder. If two or more features will want it, put it in `shared/widgets/` (that's
where `AppButton`, `AppCard`, `LoadingIndicator` live).

**A new data model:** add a plain Dart class under `core/models/`, following `user.dart`'s
pattern — `const` constructor, immutable `final` fields, a `copyWith()` for updates.

**New shared app state:** add a `ChangeNotifier` under `core/services/` and register it in the
`MultiProvider` list in `app/app.dart`, next to `AuthService`/`DatabaseService`.

## Dependencies (`pubspec.yaml`)

Dart's package manager is `pub` (pub.dev is the equivalent of npm/Maven Central). Packages are
declared in `pubspec.yaml` at the project root and installed with `flutter pub get`. Right now
the app only pulls in a handful:

- `provider` — the state management described above.
- `firebase_core`, `firebase_auth`, `cloud_firestore` — the Firebase SDKs; see
  `Authentication_and_Tasks.md`.
- `intl` — date formatting/parsing (due dates, streaks).
- `cupertino_icons` — the icon set.
- `flutter_lints` (dev-only) — the linter rules `flutter analyze` checks against.

Adding a new package: add a line under `dependencies:` in `pubspec.yaml`, run
`flutter pub get`, then `import 'package:<name>/<name>.dart';` wherever you need it.

## Tests

`test/app_smoke_test.dart` is a starting point using `flutter_test` (Flutter's equivalent of
JUnit + Espresso, unified). Run everything with:

```bash
flutter test
```

## Quick glossary

- **Widget** — a piece of UI (and its config). Everything on screen is a widget, nested inside
  other widgets.
- **`build(BuildContext context)`** — the method every widget implements to describe what it
  looks like right now. Called again ("rebuilt") whenever its inputs or watched state change.
- **`BuildContext`** — a handle to where a widget sits in the tree; used to look things up
  (theme, navigator, providers) from above.
- **`StatelessWidget` / `StatefulWidget`** — without vs. with mutable internal state.
- **`setState(() { ... })`** — tells a `StatefulWidget` "my state changed, rebuild me."
- **`ChangeNotifier` / `Provider`** — this app's shared-state mechanism; think shared
  `ViewModel` + observer.
- **Hot reload vs. hot restart** — inject changes instantly keeping state (`r`), vs. full
  restart that resets state (`R`).
- **`pubspec.yaml`** — the manifest listing dependencies, assets, and SDK constraints (Dart's
  `package.json`/`build.gradle`).
- **`Scaffold`** — the standard "page skeleton" widget (app bar + body + bottom nav, etc.).
