# QA: Walkthrough A/B Test (web, no login)

A small web build for comparing the two first-time onboarding walkthroughs:

| Variant | Source | Parent steps | Child steps |
|---|---|---|---|
| **A · Verbose** | `dev` (read live from `OnboardingGuides`) | 10 | 7 |
| **B · Minimal** | `feature/tutorial-final` (snapshot in `lib/qa/walkthrough_variants.dart`) | 4 | 4 |

It uses the real `OnboardingScreen`, but no Firebase and no sign-in. A sample
family (The Rivera Household) stands in for a logged-in account.

## Run it

```bash
flutter pub get
flutter run -d chrome -t lib/qa/ab_walkthrough_main.dart
```

## Build it for hosting

```bash
flutter build web -t lib/qa/ab_walkthrough_main.dart --no-web-resources-cdn --base-href /
# serve build/web with any static host, e.g.
python3 -m http.server 8080 -d build/web
```

If you host it in a subfolder (e.g. GitHub Pages at `/2609_team02/`), set
`--base-href /2609_team02/` instead.

## URL options

| Param | Effect |
|---|---|
| `?variant=A` / `?variant=B` | Force a variant (e.g. send each tester a fixed link) |
| `?role=parent` / `?role=child` | Pick the walkthrough role |
| `?tester=Sam` | Pre-fill the tester's name |

Without `variant`, each browser is randomly (50/50) assigned one and keeps it.
For a blind test, give testers a link without telling them which variant they got.

## What gets recorded

After each run the tester rates clarity (1–5) and can leave a comment. Each run stores:

- **outcome**: finished → tour, finished without tour, skipped, or closed/back
- **exit step / furthest step** out of total steps
- **total time** and **time spent on each step**
- tester name, role, variant, clarity rating, comment

The page shows an A vs. B summary (runs, % completed, % skipped, avg time,
avg clarity). Results live in that browser's local storage only: use
**Copy CSV** to collect them, then paste into a spreadsheet.

## Suggested QA script

1. Open the link (parent role), enter your name, tap **Start walkthrough**.
2. Go through it as a new parent would. Finish or skip, whichever feels natural.
3. Rate clarity, add a comment, **Save run**.
4. Repeat with `?role=child`.
5. **Copy CSV** and paste it into the team's results sheet.

## Files

- `lib/qa/ab_walkthrough_main.dart`: web entry point, recorder, results UI
- `lib/qa/walkthrough_variants.dart`: variant A/B definitions
- `test/qa_ab_walkthrough_test.dart`: widget tests for the QA app
- `web/`: Flutter web platform folder (needed for `flutter build web`)
