/**
 * Famotive Premium (subscriptions through the App Store / Google Play).
 *
 * - verifyPurchase (callable): the app sends a purchase; we look it up with
 *   the store, bind it to the caller and update their Premium status.
 * - appStoreNotifications (HTTPS): App Store Server Notifications V2.
 * - playStoreNotifications (Pub/Sub): Google Play real-time developer
 *   notifications on the `play-billing` topic.
 * - refreshSubscriptions (hourly): re-checks subscriptions due to renew or
 *   lapse, in case a notification was missed.
 * - syncHouseholdPremium: copies the admin's Premium end date onto
 *   `households/{id}.premiumUntil` when the admin changes.
 *
 * Data (admin-only; clients can't write any of it, see firestore.rules):
 *   subscriptions/{platform}_{hash}  one per store subscription (uid, storeId, state, expiresAt, checkAfter, ...)
 *   users/{uid}.premium              summary for the app (state, expiresAt, isTrial, willRenew, trialUsed, ...)
 *   households/{id}.premiumUntil     admin's Premium end, or null
 *   premiumGrants/{uid}              complimentary Premium (test accounts), made by hand in
 *                                    the console: optional `expiresAt` (none = forever), `note`
 *
 * Notifications are treated as hints: we take the subscription id out of
 * them and ask the store's API for the real state, so a forged notification
 * can't grant anything.
 */
import { onCall, onRequest, HttpsError } from 'firebase-functions/v2/https';
import { onMessagePublished } from 'firebase-functions/v2/pubsub';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { defineSecret, defineString } from 'firebase-functions/params';
import { logger } from 'firebase-functions';
import {
  FieldValue,
  getFirestore,
  Timestamp,
  type DocumentData,
  type DocumentSnapshot,
} from 'firebase-admin/firestore';

import {
  PREMIUM_PRODUCT_IDS,
  accountToken,
  decodeJwsPayload,
  entitlementFromApple,
  entitlementFromGoogle,
  findAppleItem,
  householdPremiumUntil,
  isEntitledState,
  sameAccountToken,
  subscriptionDocId,
  summarize,
  type Entitlement,
  type Platform,
  type PremiumState,
  type StoredSubscription,
} from './plan';
import {
  StoreError,
  appleSubscriptionStatuses,
  playAcknowledge,
  playSubscription,
  type AppleConfig,
  type AppleEnvironment,
} from './stores';

const APPLE_BUNDLE_ID = defineString('APPLE_BUNDLE_ID', { default: 'com.famotive' });
const APPLE_IAP_ISSUER_ID = defineString('APPLE_IAP_ISSUER_ID', {
  default: '',
  description: 'App Store Connect > Users and Access > Integrations > In-App Purchase: Issuer ID',
});
const APPLE_IAP_KEY_ID = defineString('APPLE_IAP_KEY_ID', {
  default: '',
  description: 'Key ID of the In-App Purchase key',
});
/** Contents of the In-App Purchase key's .p8 file. */
const APPLE_IAP_PRIVATE_KEY = defineSecret('APPLE_IAP_PRIVATE_KEY');
const ANDROID_PACKAGE_NAME = defineString('ANDROID_PACKAGE_NAME', { default: 'com.famotive' });
/** Pub/Sub topic Play Console publishes real-time developer notifications to. */
const PLAY_RTDN_TOPIC = 'play-billing';

const SUBSCRIPTIONS = 'subscriptions';
const GRANTS = 'premiumGrants';
const NOT_FOUND = 5; // gRPC

const db = () => getFirestore();

const OTHER_ACCOUNT_MESSAGE =
  'This subscription belongs to a different Famotive account. Sign in with that account, ' +
  'or manage it in your store account settings.';

function appleConfig(): AppleConfig {
  const cfg = {
    bundleId: APPLE_BUNDLE_ID.value(),
    issuerId: APPLE_IAP_ISSUER_ID.value(),
    keyId: APPLE_IAP_KEY_ID.value(),
    privateKey: APPLE_IAP_PRIVATE_KEY.value(),
  };
  if (!cfg.issuerId || !cfg.keyId || !cfg.privateKey) {
    throw new HttpsError('failed-precondition', 'App Store purchases are not configured on the server yet.');
  }
  return cfg;
}

const ms = (v: unknown): number | null => (v instanceof Timestamp ? v.toMillis() : null);
const ts = (v: number | null): Timestamp | null => (v === null ? null : Timestamp.fromMillis(v));

// --- Store lookups ---------------------------------------------------------------

interface Lookup {
  entitlement: Entitlement;
  /** originalTransactionId (iOS) or purchaseToken (Android). */
  storeId: string;
  environment: string | null;
  /** Android: the token this one replaced (upgrade / resubscribe). */
  linkedStoreId: string | null;
}

async function lookUpApple(transactionId: string, env?: AppleEnvironment): Promise<Lookup> {
  const cfg = appleConfig();
  const { env: foundIn, response } = await appleSubscriptionStatuses(cfg, transactionId, env);
  if ((response as { bundleId?: unknown })?.bundleId !== cfg.bundleId) {
    throw new HttpsError('invalid-argument', 'That purchase is for a different app.');
  }
  const item = findAppleItem(response, null);
  const tx = item ? decodeJwsPayload(item.signedTransactionInfo) : null;
  const otid = typeof tx?.originalTransactionId === 'string' ? tx.originalTransactionId : null;
  if (!item || !tx || !otid) throw new HttpsError('not-found', 'No subscription found for that purchase.');
  const renewal = item.signedRenewalInfo ? decodeJwsPayload(item.signedRenewalInfo) : null;
  return {
    entitlement: entitlementFromApple(item.status, tx, renewal, Date.now()),
    storeId: otid,
    environment: foundIn,
    linkedStoreId: null,
  };
}

async function lookUpGoogle(purchaseToken: string): Promise<Lookup> {
  const pkg = ANDROID_PACKAGE_NAME.value();
  const sub = await playSubscription(pkg, purchaseToken);
  const entitlement = entitlementFromGoogle(sub, Date.now());
  if (sub.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_PENDING' && isEntitledState(entitlement.state)) {
    try {
      await playAcknowledge(pkg, entitlement.productId, purchaseToken);
    } catch (err) {
      logger.warn('Could not acknowledge Play purchase (the app will retry)', { err: String(err) });
    }
  }
  return {
    entitlement,
    storeId: purchaseToken,
    environment: sub.testPurchase ? 'Test' : 'Production',
    linkedStoreId: typeof sub.linkedPurchaseToken === 'string' ? sub.linkedPurchaseToken : null,
  };
}

function toHttpsError(err: unknown): HttpsError {
  if (err instanceof HttpsError) return err;
  if (err instanceof StoreError) {
    logger.warn('Store lookup failed', { message: err.message });
    if (err.status === 400) return new HttpsError('invalid-argument', 'The store did not recognise that purchase.');
    if (err.status === 404 || err.status === 410) return new HttpsError('not-found', 'No subscription found for that purchase.');
    if (err.status === 401 || err.status === 403) {
      return new HttpsError('failed-precondition', 'Store purchases are not configured on the server yet.');
    }
  } else {
    logger.error('Purchase verification failed', { err: String(err) });
  }
  return new HttpsError('unavailable', 'Could not reach the store. Please try again.');
}

// --- Writing state ---------------------------------------------------------------

function subscriptionFields(uid: string, platform: Platform, l: Lookup): DocumentData {
  const e = l.entitlement;
  return {
    uid,
    platform,
    storeId: l.storeId,
    environment: l.environment,
    productId: e.productId,
    state: e.state,
    isTrial: e.isTrial,
    willRenew: e.willRenew,
    expiresAt: ts(e.expiresAtMs),
    checkAfter: ts(e.checkAfterMs),
    accountToken: e.accountToken,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function toStored(d: DocumentData): StoredSubscription {
  return {
    state: d.state as PremiumState,
    expiresAtMs: ms(d.expiresAt),
    isTrial: d.isTrial === true,
    willRenew: d.willRenew === true,
    productId: typeof d.productId === 'string' ? d.productId : '',
    platform: d.platform === 'android' ? 'android' : 'ios',
    updatedAtMs: ms(d.updatedAt) ?? 0,
  };
}

/** Recomputes `users/{uid}.premium` from the account's subscriptions and pushes it to their households. */
async function refreshAccount(uid: string) {
  const now = Date.now();
  const [snap, grantDoc] = await Promise.all([
    db().collection(SUBSCRIPTIONS).where('uid', '==', uid).get(),
    db().collection(GRANTS).doc(uid).get(),
  ]);
  const grant = grantDoc.exists ? { expiresAtMs: ms(grantDoc.get('expiresAt')) } : null;
  const summary = summarize(
    snap.docs.map((d) => toStored(d.data())),
    now,
    grant,
  );

  try {
    await db()
      .collection('users')
      .doc(uid)
      .update({
        premium: {
          state: summary.state,
          expiresAt: ts(summary.expiresAtMs),
          isTrial: summary.isTrial,
          willRenew: summary.willRenew,
          productId: summary.productId,
          platform: summary.platform,
          trialUsed: summary.trialUsed,
          updatedAt: FieldValue.serverTimestamp(),
        },
      });
  } catch (err) {
    if ((err as { code?: number }).code === NOT_FOUND) return; // account deleted
    throw err;
  }

  const owned = await db().collection('households').where('ownerId', '==', uid).get();
  const until = householdPremiumUntil(summary, now);
  await Promise.all(
    owned.docs
      .filter((h) => ms(h.get('premiumUntil')) !== until)
      .map((h) => h.ref.update({ premiumUntil: ts(until) })),
  );
  return summary;
}

/** Re-asks the store about a stored subscription and updates everything that depends on it. */
async function refreshSubscription(doc: DocumentSnapshot) {
  const d = doc.data();
  if (!d || typeof d.uid !== 'string' || typeof d.storeId !== 'string') return;
  const platform: Platform = d.platform === 'android' ? 'android' : 'ios';
  let lookup: Lookup;
  try {
    lookup =
      platform === 'ios'
        ? await lookUpApple(d.storeId, d.environment === 'Sandbox' || d.environment === 'Production' ? d.environment : undefined)
        : await lookUpGoogle(d.storeId);
  } catch (err) {
    // Google drops tokens of long-expired subscriptions (410).
    if (err instanceof StoreError && (err.status === 404 || err.status === 410)) {
      await doc.ref.update({ state: 'expired', expiresAt: null, checkAfter: null, updatedAt: FieldValue.serverTimestamp() });
      await refreshAccount(d.uid);
      return;
    }
    throw err;
  }
  await doc.ref.set(subscriptionFields(d.uid, platform, lookup));
  if (lookup.linkedStoreId) await markReplaced(platform, lookup.linkedStoreId, d.uid);
  await refreshAccount(d.uid);
}

async function markReplaced(platform: Platform, storeId: string, uid: string) {
  const ref = db().collection(SUBSCRIPTIONS).doc(subscriptionDocId(platform, storeId));
  const snap = await ref.get();
  if (!snap.exists || snap.get('uid') !== uid || snap.get('state') === 'replaced') return;
  await ref.update({ state: 'replaced', expiresAt: null, checkAfter: null, updatedAt: FieldValue.serverTimestamp() });
}

/** Account deletion: forget the account's store subscriptions (it should be cancelled in the store too). */
export async function forgetSubscriptions(uid: string) {
  const snap = await db().collection(SUBSCRIPTIONS).where('uid', '==', uid).get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}

// --- Functions -------------------------------------------------------------------

/**
 * Called by the app after a purchase or restore.
 * data: { platform: 'ios', transactionId } | { platform: 'android', purchaseToken }
 * Returns the account's Premium summary.
 */
export const verifyPurchase = onCall({ invoker: 'public', secrets: [APPLE_IAP_PRIVATE_KEY] }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const data = (request.data ?? {}) as Record<string, unknown>;
  const platform = data.platform;
  const storeId = platform === 'ios' ? data.transactionId : data.purchaseToken;
  if ((platform !== 'ios' && platform !== 'android') || typeof storeId !== 'string' || !storeId || storeId.length > 4096) {
    throw new HttpsError('invalid-argument', 'Missing purchase details.');
  }

  const user = await db().collection('users').doc(uid).get();
  if (user.get('role') !== 'parent') {
    throw new HttpsError('permission-denied', 'Only parent accounts can subscribe to Premium.');
  }

  let lookup: Lookup;
  try {
    lookup = platform === 'ios' ? await lookUpApple(storeId) : await lookUpGoogle(storeId);
  } catch (err) {
    throw toHttpsError(err);
  }
  const e = lookup.entitlement;
  if (!PREMIUM_PRODUCT_IDS.has(e.productId)) {
    throw new HttpsError('invalid-argument', 'That purchase is not a Famotive Premium subscription.');
  }
  // Purchases made in the app carry the buyer's account token.
  if (e.accountToken && !sameAccountToken(e.accountToken, accountToken(uid))) {
    throw new HttpsError('failed-precondition', OTHER_ACCOUNT_MESSAGE);
  }

  const ref = db().collection(SUBSCRIPTIONS).doc(subscriptionDocId(platform, lookup.storeId));
  await db().runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    const owner = existing.get('uid');
    if (existing.exists && owner !== uid && !e.accountToken) {
      throw new HttpsError('failed-precondition', OTHER_ACCOUNT_MESSAGE);
    }
    tx.set(ref, subscriptionFields(uid, platform, lookup));
  });
  if (lookup.linkedStoreId) await markReplaced(platform, lookup.linkedStoreId, uid);

  const summary = await refreshAccount(uid);
  logger.info('Purchase verified', { uid, platform, state: e.state, productId: e.productId });
  return {
    state: summary?.state ?? e.state,
    expiresAt: summary?.expiresAtMs ?? null,
    isTrial: summary?.isTrial ?? e.isTrial,
  };
});

/**
 * App Store Server Notifications V2. Set this function's URL as the
 * Production and Sandbox Server URL in App Store Connect (App Information).
 */
export const appStoreNotifications = onRequest({ secrets: [APPLE_IAP_PRIVATE_KEY] }, async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).send('');
    return;
  }
  const payload = decodeJwsPayload((req.body as { signedPayload?: unknown } | undefined)?.signedPayload);
  if (!payload) {
    res.status(400).send('');
    return;
  }
  const type = String(payload.notificationType ?? '');
  const data = (payload.data ?? {}) as Record<string, unknown>;
  if (type === 'TEST' || data.bundleId !== APPLE_BUNDLE_ID.value()) {
    logger.info('App Store notification ignored', { type, bundleId: data.bundleId });
    res.status(200).send('');
    return;
  }
  const otid = decodeJwsPayload(data.signedTransactionInfo)?.originalTransactionId;
  const doc =
    typeof otid === 'string'
      ? await db().collection(SUBSCRIPTIONS).doc(subscriptionDocId('ios', otid)).get()
      : null;
  if (!doc?.exists) {
    // Not verified by the app yet; it will be when the app sees the purchase.
    logger.info('App Store notification for an unknown subscription', { type });
    res.status(200).send('');
    return;
  }
  try {
    await refreshSubscription(doc);
    logger.info('App Store notification handled', { type, subtype: payload.subtype, uid: doc.get('uid') });
    res.status(200).send('');
  } catch (err) {
    logger.error('App Store notification failed (Apple will retry)', { type, err: String(err) });
    res.status(500).send('');
  }
});

/**
 * Google Play real-time developer notifications. In Play Console >
 * Monetization setup, set the topic to projects/<project>/topics/play-billing.
 */
export const playStoreNotifications = onMessagePublished(PLAY_RTDN_TOPIC, async (event) => {
  let msg: Record<string, unknown>;
  try {
    msg = event.data.message.json as Record<string, unknown>;
  } catch {
    logger.warn('Unreadable Play notification');
    return;
  }
  if (msg?.testNotification) {
    logger.info('Play test notification received');
    return;
  }
  const note = msg?.subscriptionNotification as { purchaseToken?: unknown; notificationType?: unknown } | undefined;
  if (msg?.packageName !== ANDROID_PACKAGE_NAME.value() || typeof note?.purchaseToken !== 'string') return;

  const doc = await db().collection(SUBSCRIPTIONS).doc(subscriptionDocId('android', note.purchaseToken)).get();
  if (!doc.exists) {
    logger.info('Play notification for an unknown subscription', { type: note.notificationType });
    return;
  }
  // Throwing makes Pub/Sub redeliver.
  await refreshSubscription(doc);
  logger.info('Play notification handled', { type: note.notificationType, uid: doc.get('uid') });
});

/** A complimentary grant was added, changed or removed: recompute that account. */
export const onPremiumGrantWritten = onDocumentWritten(`${GRANTS}/{uid}`, async (event) => {
  await refreshAccount(event.params.uid);
  logger.info('Complimentary Premium updated', { uid: event.params.uid, granted: !!event.data?.after.exists });
});

/** Backstop for missed notifications: re-checks subscriptions that are due. */
export const refreshSubscriptions = onSchedule(
  { schedule: 'every 1 hours', timeZone: 'UTC', secrets: [APPLE_IAP_PRIVATE_KEY] },
  async () => {
    const due = await db()
      .collection(SUBSCRIPTIONS)
      .where('checkAfter', '<=', Timestamp.now())
      .orderBy('checkAfter')
      .limit(200)
      .get();
    let failed = 0;
    for (const doc of due.docs) {
      try {
        await refreshSubscription(doc);
      } catch (err) {
        failed++;
        logger.warn('Subscription refresh failed', { id: doc.id, err: String(err) });
      }
    }
    if (due.size) logger.info('Refreshed subscriptions', { checked: due.size, failed });
  },
);

/**
 * A household's admin changed (or the household was just created): copy the
 * new admin's Premium onto the household. Also undoes any other change to
 * premiumUntil (the rules don't allow clients to make one).
 */
export const syncHouseholdPremium = onDocumentWritten('households/{householdId}', async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!after) return;
  if (before && before.ownerId === after.ownerId && ms(before.premiumUntil) === ms(after.premiumUntil)) return;

  const owner = typeof after.ownerId === 'string' ? await db().collection('users').doc(after.ownerId).get() : null;
  const until = householdPremiumUntil({ expiresAtMs: ms(owner?.get('premium.expiresAt')) }, Date.now());
  if (ms(after.premiumUntil) === until) return;
  await event.data!.after.ref.update({ premiumUntil: ts(until) });
});
