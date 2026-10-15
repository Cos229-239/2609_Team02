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

## Deploy to famotive.org/qa/walkthrough (Firebase Hosting)

The QA app is served from a sub-path of the existing site:
**https://famotive.org/qa/walkthrough** (e.g. `.../qa/walkthrough?variant=B&role=child`).

```bash
tool/deploy_qa_walkthrough.sh            # build into public/qa/walkthrough/ only
tool/deploy_qa_walkthrough.sh --preview  # + deploy to a 14-day preview URL (live site untouched)
tool/deploy_qa_walkthrough.sh --deploy   # + deploy to the live site
```

**Read this before deploying.** A Hosting deploy replaces the *whole* site
with `public/`. The site's own pages are **not in this repo**: `index.html`,
`privacy-policy.html`, `delete-my-data.html` and `.well-known/`. The
`.well-known/` files are what make Android/iOS app links and password-reset
links work. So:

1. Get the site's current `public/` folder from whoever deploys famotive.org
   and put it at the repo root (`public/qa/` is git-ignored; the rest isn't
   committed today).
2. Run with `--preview` first and check the main pages, `/.well-known/assetlinks.json`
   and `/qa/walkthrough` on the preview URL.
3. Then run `--deploy`.

The script refuses `--preview`/`--deploy` if any of those site files are missing.

`firebase.json` hosting changes for this:

- `/qa/**` is sent with `X-Robots-Tag: noindex` so search engines skip it.
- The QA app's `index.html` / bootstrap files are `no-cache`, so testers get new builds right away.
- `/qa/walkthrough/**` rewrites to the app's `index.html`.
- `ignore` no longer contains `**/.*`. That pattern would have left
  `.well-known/` out of the deploy and broken app links.

Note: the live site doesn't currently match this repo's `hosting` config
(e.g. `/privacy-policy` without `.html` is a 404 live, but `cleanUrls: true`
here would redirect `/privacy-policy.html` → `/privacy-policy`). Check with
whoever deploys the site whether they use a different `firebase.json` before
using this one for a live deploy.

To serve the build locally without Firebase:

```bash
flutter build web -t lib/qa/ab_walkthrough_main.dart --no-web-resources-cdn
python3 -m http.server 8080 -d build/web
```

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
- `tool/deploy_qa_walkthrough.sh`: build into `public/qa/walkthrough/` and (optionally) deploy
