# Famotive Premium — setup

Premium unlocks **photo proof** for tasks. It's a subscription on a parent's
account, and it applies to every household that parent is the **admin** of.
New subscribers get a **7-day free trial** (the store's introductory offer),
then it renews through the App Store / Google Play.

## How it works

```
App (in_app_purchase)  →  store purchase sheet (trial terms shown by the store)
        │ purchaseID (iOS) / purchaseToken (Android)
        ▼
verifyPurchase (Cloud Function) → App Store Server API / Play Developer API
        │ writes
        ▼
subscriptions/{id}          server-only record of each store subscription
users/{uid}.premium         summary the app shows (state, expiresAt, isTrial, trialUsed…)
households/{id}.premiumUntil  admin's Premium end; rules + app check this
```

- Renewals, cancellations, refunds and billing problems arrive as store
  notifications (`appStoreNotifications`, `playStoreNotifications`). They are
  treated as hints: the function re-reads the subscription from the store's
  API, so a forged notification can't grant anything.
- `refreshSubscriptions` (hourly) re-checks anything due to renew or lapse in
  case a notification was missed.
- When the admin role moves to another parent, `syncHouseholdPremium` copies
  the new admin's Premium onto the household.
- Each purchase is tagged with an account token (a UUID derived from the
  Firebase uid; Apple `appAccountToken`, Google `obfuscatedAccountId`). A
  subscription can only be claimed by the Famotive account that bought it.
- Without Premium (never had it, or it lapsed): the "Require Photo Proof"
  switch is replaced by a Premium tile (admin → Premium screen; other parents
  are told to ask the admin). Existing photo tasks can be finished without a
  photo, and Storage rejects new proof uploads. Nothing is deleted, so photo
  proof comes back on its own if Premium resumes.
- Only parents can subscribe (server-enforced). Children never see the
  paywall.

Product ids (same in both stores, in `PremiumProducts` and
`functions/src/premium/plan.ts`):

| Product id | Period |
|---|---|
| `famotive_premium_monthly` | 1 month |
| `famotive_premium_yearly` | 1 year |

## One-time store setup

### App Store Connect
1. Agreements, Tax and Banking: the **Paid Apps** agreement must be active.
2. App → Monetization → **Subscriptions**: create one subscription group
   ("Famotive Premium") with the two products above.
3. On each product add an **Introductory Offer → Free → 1 week**, all
   territories.
4. Users and Access → Integrations → **In-App Purchase**: generate a key.
   Note the **Issuer ID** and **Key ID**, download the `.p8`.
5. App Information → **App Store Server Notifications**: Version 2, set both
   Production and Sandbox URLs to the `appStoreNotifications` function URL
   (shown after deploy, e.g.
   `https://appstorenotifications-<hash>-uc.a.run.app`).
6. Nothing to add in Xcode: In-App Purchase is on for every App ID by
   default and needs no entitlement, so recent Xcode versions don't list it
   under Signing & Capabilities.

### Google Play Console
1. Monetize → Products → **Subscriptions**: create the two products, each
   with a base plan (monthly / yearly, auto-renewing) and an **offer**
   "free-trial": *new customer acquisition*, phase **Free trial, 7 days**.
2. Monetization setup → **Real-time developer notifications**: topic
   `projects/famotive-8c858/topics/play-billing` (create the topic in Google
   Cloud Pub/Sub first and grant
   `google-play-developer-notifications@system.gserviceaccount.com` the
   *Pub/Sub Publisher* role on it). Send a test notification.
3. Users and permissions → invite the Cloud Functions service account
   (`451691992012-compute@developer.gserviceaccount.com`, the default compute
   account used by 2nd-gen functions) with **View financial data** and
   **Manage orders and subscriptions**.
4. Enable the **Google Play Android Developer API** in the Google Cloud
   project.
5. Billing requires an app build uploaded to a testing track; add license
   testers to test without being charged.

### Firebase
```sh
# Apple key (paste the whole .p8 file contents)
firebase functions:secrets:set APPLE_IAP_PRIVATE_KEY < AuthKey_XXXXXXXXXX.p8

# functions/.env  (deploy reads these params)
APPLE_IAP_ISSUER_ID=<issuer id>
APPLE_IAP_KEY_ID=<key id>
# defaults: APPLE_BUNDLE_ID=com.famotive, ANDROID_PACKAGE_NAME=com.famotive

firebase deploy --only functions,firestore:rules,storage
```

## Test accounts (complimentary Premium)
Give an account Premium without a purchase: in the Firebase console →
Firestore, create a document in the **`premiumGrants`** collection whose ID is
the account's **uid**. Fields are optional: `note` (string, e.g. "test
account") and `expiresAt` (timestamp; leave it out for no end). The
`onPremiumGrantWritten` function then updates `users/{uid}.premium` (state
`complimentary`) and the `premiumUntil` of the households that account is the
admin of. Delete the document to take it away. Clients can't read or write
this collection.

## Testing
- iOS: sandbox Apple account (Settings → App Store → Sandbox Account) or a
  StoreKit configuration file in Xcode. Sandbox renews monthly plans every
  5 minutes and the 1-week trial in ~3 minutes, so renewal / expiry handling
  can be watched in the `users/{uid}.premium` doc.
- Android: license testers; test subscriptions renew every few minutes.
- Things to check: trial starts and Premium turns on; "Require Photo Proof"
  unlocks; cancel → shows "Cancelled, stays on until …"; let it expire →
  photo tasks finish without a photo; Restore Purchases on a reinstall;
  restoring on a *different* Famotive account is refused; handing the admin
  role to a non-Premium parent turns photo proof off in that household.

## Not done / follow-ups
- Firestore/Storage rules changes haven't been run through the emulator.
- iOS trial eligibility shown in the app is based on our own record
  (`trialUsed`); the store sheet always shows the real terms.
- Upgrading monthly → yearly on Android is done from Play's subscription
  page (the app shows Manage Subscription once subscribed).
- The App Store Connect review needs a screenshot of the paywall and the
  Terms / Privacy links (both are on the Premium screen).
