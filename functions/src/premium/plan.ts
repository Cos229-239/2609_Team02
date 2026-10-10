/**
 * Famotive Premium: pure logic (no Firestore / network), unit-tested in
 * plan.test.ts. The I/O lives in ./index.ts and ./stores.ts.
 *
 * Premium belongs to an account. A household gets Premium features (photo
 * proof) while its admin (ownerId) has Premium; the server mirrors that onto
 * `households/{id}.premiumUntil` so every member's app and the security rules
 * can check it with one read.
 *
 * The 7-day free trial is the subscription's introductory offer in App Store
 * Connect / Play Console, so the stores decide who is eligible and convert it
 * to a paid subscription on day 8.
 */
import { createHash } from 'node:crypto';

/** Store product ids. Keep in sync with PremiumProducts in lib/core/constants/app_constants.dart. */
export const PREMIUM_PRODUCT_IDS = new Set(['famotive_premium_monthly', 'famotive_premium_yearly']);

export type Platform = 'ios' | 'android';

/**
 * Where a subscription stands. Entitled states: trial, active, canceled
 * (auto-renew off, still paid up) and grace (renewal failed, store grace
 * period). Not entitled: billing_retry, on_hold, paused, pending, expired,
 * revoked (refunded), replaced (superseded by an upgrade / resubscribe).
 */
export type PremiumState =
  | 'complimentary'
  | 'trial'
  | 'active'
  | 'canceled'
  | 'grace'
  | 'billing_retry'
  | 'on_hold'
  | 'paused'
  | 'pending'
  | 'expired'
  | 'revoked'
  | 'replaced';

export interface Entitlement {
  state: PremiumState;
  /** End of access in ms, or null when not entitled. */
  expiresAtMs: number | null;
  isTrial: boolean;
  willRenew: boolean;
  productId: string;
  /** The account token the purchase was made with (appAccountToken / obfuscatedExternalAccountId). */
  accountToken: string | null;
  /** When to ask the store again (ms), or null for terminal states. */
  checkAfterMs: number | null;
}

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
/** Re-check a lapsed-but-recoverable subscription (billing retry / on hold / paused) this often. */
const RECHECK_LAPSED_MS = DAY;

/**
 * The UUID a purchase is tagged with so the server can tell which Famotive
 * account bought it (Apple appAccountToken must be a UUID; Google takes it as
 * obfuscatedAccountId). Derived from the uid; the app computes the same value
 * (PremiumService.accountToken).
 */
export function accountToken(uid: string): string {
  const b = createHash('sha256').update(`famotive:${uid}`).digest().subarray(0, 16);
  b[6] = (b[6] & 0x0f) | 0x50; // version 5 (name-based)
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
  const h = b.toString('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

export function sameAccountToken(a: string | null | undefined, b: string | null | undefined): boolean {
  return !!a && !!b && a.toLowerCase() === b.toLowerCase();
}

/**
 * Payload of a JWS (header.payload.signature) WITHOUT checking the
 * signature. Only used on data fetched from Apple's API over TLS with our own
 * credentials, or to pull an id out of an (untrusted) notification that is
 * then looked up through that API.
 */
export function decodeJwsPayload(jws: unknown): Record<string, unknown> | null {
  if (typeof jws !== 'string') return null;
  const parts = jws.split('.');
  if (parts.length !== 3) return null;
  try {
    const value = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    return value && typeof value === 'object' ? (value as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

function num(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

function str(v: unknown): string | null {
  return typeof v === 'string' && v.length > 0 ? v : null;
}

function checkAfter(state: PremiumState, expiresAtMs: number | null, now: number): number | null {
  switch (state) {
    case 'trial':
    case 'active':
    case 'canceled':
    case 'grace':
      // Right after it should have renewed (or lapsed).
      return expiresAtMs ?? now + RECHECK_LAPSED_MS;
    case 'billing_retry':
    case 'on_hold':
    case 'paused':
    case 'pending':
      return now + RECHECK_LAPSED_MS;
    default:
      return null;
  }
}

function finish(e: Omit<Entitlement, 'checkAfterMs'>, now: number): Entitlement {
  // Anything already past its end date is expired, whatever the store said.
  if (e.expiresAtMs !== null && e.expiresAtMs <= now) {
    e = { ...e, state: e.state === 'revoked' ? 'revoked' : 'expired', expiresAtMs: null, willRenew: false };
  }
  if (e.expiresAtMs === null && isEntitledState(e.state)) {
    e = { ...e, state: 'expired', willRenew: false };
  }
  return { ...e, checkAfterMs: checkAfter(e.state, e.expiresAtMs, now) };
}

export function isEntitledState(state: PremiumState): boolean {
  return (
    state === 'complimentary' || state === 'trial' || state === 'active' || state === 'canceled' || state === 'grace'
  );
}

// --- Apple ------------------------------------------------------------------

/** App Store Server API `lastTransactions[].status` values. */
const APPLE_STATUS = { active: 1, expired: 2, billingRetry: 3, grace: 4, revoked: 5 } as const;

/**
 * Entitlement from one `lastTransactions` item of the App Store Server API's
 * Get All Subscription Statuses response (`status`, decoded
 * `signedTransactionInfo`, decoded `signedRenewalInfo`).
 */
export function entitlementFromApple(
  status: number,
  tx: Record<string, unknown>,
  renewal: Record<string, unknown> | null,
  now: number,
): Entitlement {
  const productId = str(tx.productId) ?? '';
  const expires = num(tx.expiresDate);
  const graceEnd = num(renewal?.gracePeriodExpiresDate);
  // offerType 1 = introductory offer. Older transactions have no
  // offerDiscountType; our only intro offer is the free trial.
  const isTrial =
    num(tx.offerType) === 1 && (tx.offerDiscountType === undefined || tx.offerDiscountType === 'FREE_TRIAL');
  const willRenew = num(renewal?.autoRenewStatus) === 1;
  const base = { productId, isTrial: false, willRenew: false, accountToken: str(tx.appAccountToken) };

  if (num(tx.revocationDate) !== null || status === APPLE_STATUS.revoked) {
    return finish({ ...base, state: 'revoked', expiresAtMs: null }, now);
  }
  switch (status) {
    case APPLE_STATUS.active:
      return finish(
        { ...base, isTrial, willRenew, state: isTrial ? 'trial' : willRenew ? 'active' : 'canceled', expiresAtMs: expires },
        now,
      );
    case APPLE_STATUS.grace:
      return finish({ ...base, willRenew, state: 'grace', expiresAtMs: graceEnd ?? expires }, now);
    case APPLE_STATUS.billingRetry:
      return finish({ ...base, willRenew, state: 'billing_retry', expiresAtMs: null }, now);
    default:
      return finish({ ...base, state: 'expired', expiresAtMs: null }, now);
  }
}

/** Picks the item for [originalTransactionId] out of a Get All Subscription Statuses response. */
export function findAppleItem(
  response: unknown,
  originalTransactionId: string | null,
): { status: number; signedTransactionInfo: string; signedRenewalInfo?: string } | null {
  const groups = (response as { data?: unknown })?.data;
  if (!Array.isArray(groups)) return null;
  const items: { status: number; signedTransactionInfo: string; signedRenewalInfo?: string; otid: string | null }[] = [];
  for (const g of groups) {
    const last = (g as { lastTransactions?: unknown })?.lastTransactions;
    if (!Array.isArray(last)) continue;
    for (const it of last) {
      const status = num(it?.status);
      const signed = str(it?.signedTransactionInfo);
      if (status === null || !signed) continue;
      items.push({
        status,
        signedTransactionInfo: signed,
        signedRenewalInfo: str(it?.signedRenewalInfo) ?? undefined,
        otid: str(it?.originalTransactionId) ?? str(decodeJwsPayload(signed)?.originalTransactionId),
      });
    }
  }
  const match = items.find((i) => originalTransactionId !== null && i.otid === originalTransactionId) ?? items[0];
  if (!match) return null;
  const { otid: _ignored, ...rest } = match;
  return rest;
}

// --- Google -----------------------------------------------------------------

/**
 * Entitlement from a Google Play Developer API
 * `purchases.subscriptionsv2.get` response.
 */
export function entitlementFromGoogle(sub: Record<string, unknown>, now: number): Entitlement {
  const lineItems = Array.isArray(sub.lineItems) ? (sub.lineItems as Record<string, unknown>[]) : [];
  let item: Record<string, unknown> | undefined;
  let expires: number | null = null;
  for (const li of lineItems) {
    const t = Date.parse(String(li.expiryTime ?? ''));
    if (Number.isFinite(t) && (expires === null || t > expires)) {
      expires = t;
      item = li;
    }
  }
  item ??= lineItems[0];
  const productId = str(item?.productId) ?? '';
  const offer = (item?.offerDetails ?? {}) as Record<string, unknown>;
  const phase = (item?.offerPhase ?? {}) as Record<string, unknown>;
  const tags = Array.isArray(offer.offerTags) ? (offer.offerTags as unknown[]) : [];
  const isTrial =
    phase.freeTrial !== undefined ||
    (phase.basePrice === undefined && (/trial/i.test(String(offer.offerId ?? '')) || tags.some((t) => /trial/i.test(String(t)))));
  const willRenew = (item?.autoRenewingPlan as Record<string, unknown> | undefined)?.autoRenewEnabled === true;
  const ids = (sub.externalAccountIdentifiers ?? {}) as Record<string, unknown>;
  const base = {
    productId,
    isTrial: false,
    willRenew: false,
    accountToken: str(ids.obfuscatedExternalAccountId),
  };

  switch (String(sub.subscriptionState ?? '')) {
    case 'SUBSCRIPTION_STATE_ACTIVE':
      return finish(
        { ...base, isTrial, willRenew, state: isTrial ? 'trial' : willRenew ? 'active' : 'canceled', expiresAtMs: expires },
        now,
      );
    case 'SUBSCRIPTION_STATE_CANCELED':
      return finish({ ...base, isTrial, state: 'canceled', expiresAtMs: expires }, now);
    case 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD':
      return finish({ ...base, willRenew, state: 'grace', expiresAtMs: expires }, now);
    case 'SUBSCRIPTION_STATE_ON_HOLD':
      return finish({ ...base, state: 'on_hold', expiresAtMs: null }, now);
    case 'SUBSCRIPTION_STATE_PAUSED':
      return finish({ ...base, state: 'paused', expiresAtMs: null }, now);
    case 'SUBSCRIPTION_STATE_PENDING':
      return finish({ ...base, state: 'pending', expiresAtMs: null }, now);
    default:
      // EXPIRED, PENDING_PURCHASE_CANCELED, unknown.
      return finish({ ...base, state: 'expired', expiresAtMs: null }, now);
  }
}

/** Firestore doc id for a subscription (purchase tokens are long, so they're hashed). */
export function subscriptionDocId(platform: Platform, storeId: string): string {
  return `${platform}_${createHash('sha256').update(storeId).digest('hex').slice(0, 40)}`;
}

// --- Account / household summaries -----------------------------------------

export interface StoredSubscription {
  state: PremiumState;
  expiresAtMs: number | null;
  isTrial: boolean;
  willRenew: boolean;
  productId: string;
  platform: Platform;
  updatedAtMs: number;
}

export interface PremiumSummary {
  state: PremiumState | 'none';
  /** Access ends at (ms); null when not entitled. */
  expiresAtMs: number | null;
  isTrial: boolean;
  willRenew: boolean;
  productId: string | null;
  platform: Platform | null;
  /** Has this account ever started a subscription (so the free trial is used up)? */
  trialUsed: boolean;
}

/**
 * Complimentary Premium (test / staff accounts): `premiumGrants/{uid}`,
 * created by hand in the Firebase console. No `expiresAt` = never ends,
 * stored as this date so households and rules have a timestamp to compare.
 */
export const COMPLIMENTARY_FOREVER_MS = Date.UTC(2099, 11, 31);

export interface PremiumGrant {
  /** End of the grant in ms, or null for no end. */
  expiresAtMs: number | null;
}

/**
 * What `users/{uid}.premium` should say given all of the account's
 * subscriptions (and any complimentary grant): the entitled one that runs
 * longest, else the most recently updated one.
 */
export function summarize(subs: StoredSubscription[], now: number, grant?: PremiumGrant | null): PremiumSummary {
  const paid = summarizeSubscriptions(subs, now);
  const grantEnd = grant ? grant.expiresAtMs ?? COMPLIMENTARY_FOREVER_MS : null;
  if (grantEnd === null || grantEnd <= now || (paid.expiresAtMs !== null && paid.expiresAtMs >= grantEnd)) {
    return paid;
  }
  return {
    state: 'complimentary',
    expiresAtMs: grantEnd,
    isTrial: false,
    willRenew: false,
    productId: null,
    platform: null,
    trialUsed: paid.trialUsed,
  };
}

function summarizeSubscriptions(subs: StoredSubscription[], now: number): PremiumSummary {
  const live = subs
    .filter((s) => isEntitledState(s.state) && s.expiresAtMs !== null && s.expiresAtMs > now)
    .sort((a, b) => b.expiresAtMs! - a.expiresAtMs!);
  const pick = live[0] ?? [...subs].sort((a, b) => b.updatedAtMs - a.updatedAtMs)[0];
  if (!pick) {
    return { state: 'none', expiresAtMs: null, isTrial: false, willRenew: false, productId: null, platform: null, trialUsed: false };
  }
  const entitled = live.length > 0;
  return {
    state: entitled ? pick.state : pick.state === 'replaced' || isEntitledState(pick.state) ? 'expired' : pick.state,
    expiresAtMs: entitled ? pick.expiresAtMs : null,
    isTrial: entitled && pick.isTrial,
    willRenew: entitled && pick.willRenew,
    productId: pick.productId,
    platform: pick.platform,
    trialUsed: true,
  };
}

/** `households/{id}.premiumUntil` (ms) for a household whose admin has [owner]'s premium summary. */
export function householdPremiumUntil(owner: { expiresAtMs?: number | null } | null | undefined, now: number): number | null {
  const until = owner?.expiresAtMs ?? null;
  return until !== null && until > now ? until : null;
}

