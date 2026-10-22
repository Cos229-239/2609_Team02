# QA: Walkthrough A/B Test (web, no login)

A small web build for comparing the two first-time onboarding walkthroughs:

| Variant | Source | Parent steps | Child steps |
|---|---|---|---|
| **A · Verbose** | `dev` (read live from `OnboardingGuides`) | 10 | 7 |
| **B · Minimal** | `feature/tutorial-final` (snapshot in `lib/qa/walkthrough_variants.dart`) + a "Meet Rex!" screen for kids | 4 | 5 |

> **Currently pinned: every run is Version B, child view.** Testers kept
> reporting Version A, so `kOnlyVariant = WalkthroughVariant.b` and
> `kOnlyRole = UserRole.child` at the top of `lib/qa/ab_walkthrough_main.dart`
> override the random pick, the `?variant=` / `?role=` URL options and the
> setup screen. Set both back to `null` to go back to random A/B runs.
>
> In the demo, **Rex's Room works in the browser** (an iframe instead of the
> app's WebView, `lib/features/rex/host/`) and **every Rex item is unlocked**
> (toys, decor, hat, Ptero Pal, 99 of each care item) so testers can try them
> all. The child's Account Settings show the `feature/child-first` rules
> (picture only; a parent changes name, age, email and password).

Each run shows the real `OnboardingScreen`, then opens **the whole app** on
sample data (The Rivera Household: parent Alex, kids Maya and Leo, tasks in
every state, repeating chores, the starter rewards). There's no Firebase and no
sign-in: the QA build never initializes Firebase, and the app runs on an
in-memory Firestore and a mock sign-in (`lib/qa/demo_family.dart`) that are
created fresh for each run and thrown away afterwards. Nothing a tester does is
saved anywhere or reaches real data. Account deletion is turned off in the demo.

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
- The QA app's `index.html`, bootstrap files and `main.dart.js` are `no-cache`, so testers get new builds right away.
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

## How a run works

1. Opening the link starts right away (no setup screen). The variant (A/B)
   and the role (parent/child) are each picked at random (50/50) for every run
   (while pinned, see above: always B as a child).
2. The walkthrough for that variant and role. A large, faint **VERSION A** /
   **VERSION B** watermark sits over the screen for the whole run, so
   screenshots and screen recordings show which version was tested.
3. When the walkthrough ends (finished, skipped or closed), the full app opens
   signed in as the demo parent or child, like the real hand-off. If the
   tester picked the spotlight tour, it plays.
4. In **Settings**, **Log Out** is replaced by **End test**. Tapping it closes
   the app and shows a thank-you card with the version, a run code and
   **Take the survey**, which opens the external survey in a new tab.
   **Test again** starts a new random run.

## The survey

Ratings and comments are collected in an external survey, not in the app.
Set its link in `kSurveyUrl` at the top of `lib/qa/ab_walkthrough_main.dart`
(or per link with `?survey=`). These placeholders are filled in:

| Placeholder | Becomes |
|---|---|
| `{version}` | `A` or `B` |
| `{role}` | `parent` or `child` |
| `{run}` | the run code shown to the tester (matches the timing log) |
| `{tester}` | the `?tester=` name, if given |

For a Google Form: **⋮ → Get pre-filled link**, type `VERSION` and `ROLE` as
answers to the version/role questions, copy the link and replace those words
with `{version}` and `{role}`, e.g.
`https://docs.google.com/forms/d/e/<id>/viewform?usp=pp_url&entry.111={version}&entry.222={role}&entry.333={run}`.

The survey is the Tally form **Famotive Walkthrough A/B Test**
(https://tally.so/r/LD1bez). The app opens it as
`https://tally.so/r/LD1bez?version={version}&role={role}&run={run}&tester={tester}`.
Tally only keeps those values if the form has **Hidden fields** with the same
names (`version`, `role`, `run`, `tester`); add them in the Tally editor
(type `/hidden`) to get them with every answer.

## URL options

| Param | Effect |
|---|---|
| `?variant=A` / `?variant=B` | Force a variant instead of picking at random |
| `?role=parent` / `?role=child` | Force the role instead of picking at random |
| `?tester=Sam` | Tester's name, passed to the survey (`{tester}`) and saved with the run |
| `?survey=<url>` | Use this survey link instead of `kSurveyUrl` (URL-encode it) |
| `?setup=1` | Show the manual setup + results screen instead (pick role/variant by hand) |

The thank-you card also has a **Setup & results** link to the same screen.

## What gets recorded (in the browser)

Each run stores, in that browser's local storage:

- **run code**, tester, role, variant
- **outcome**: finished → tour, finished without tour, skipped, or closed/back
- **exit step / furthest step** out of total steps
- **walkthrough time** and **time spent on each step**
- **time in the app** until End test

**Setup & results** shows an A vs. B summary (runs, % completed, % skipped,
average walkthrough time, average time in the app). Use **Copy CSV** to
collect the log, and match it to survey answers by run code.

## Suggested QA script

1. Open https://famotive.org/qa/walkthrough (add `?tester=YourName` if you like).
2. Go through the walkthrough as a new parent or child would (whichever role
   you got). Finish or skip, whichever feels natural.
3. Use the app for a few minutes: try the main things that role does.
4. Go to **Settings → End test**, then **Take the survey**.
5. Tap **Test again** for another random version.

## Files

- `lib/qa/ab_walkthrough_main.dart`: web entry point, watermark, recorder, survey link, results UI
- `lib/qa/walkthrough_variants.dart`: variant A/B definitions
- `lib/qa/demo_family.dart`: the sample household and the in-memory demo session
- `lib/core/services/demo_mode.dart`: lets the app swap **Log Out** for **End test**
- `test/qa_ab_walkthrough_test.dart`: widget tests for the QA app
- `web/`: Flutter web platform folder (needed for `flutter build web`)
- `tool/deploy_qa_walkthrough.sh`: build into `public/qa/walkthrough/` and (optionally) deploy
