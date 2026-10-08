import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  COMPLIMENTARY_FOREVER_MS,
  accountToken,
  decodeJwsPayload,
  entitlementFromApple,
  entitlementFromGoogle,
  findAppleItem,
  householdPremiumUntil,
  sameAccountToken,
  subscriptionDocId,
  summarize,
  type StoredSubscription,
} from './plan';

const NOW = Date.UTC(2026, 9, 7, 12);
const DAY = 24 * 60 * 60 * 1000;
const jws = (payload: object) =>
  `${Buffer.from('{"alg":"ES256"}').toString('base64url')}.${Buffer.from(JSON.stringify(payload)).toString('base64url')}.sig`;

test('accountToken is a stable, lower-case v5-style UUID per uid', () => {
  const a = accountToken('uid-1');
  assert.match(a, /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.equal(a, accountToken('uid-1'));
  assert.notEqual(a, accountToken('uid-2'));
  // Golden value: lib/core/services/premium_service.dart must produce the same.
  assert.equal(accountToken('abc'), 'a75d7b44-b1e4-5cba-ad60-5ae51139f501');
  assert.ok(sameAccountToken(a.toUpperCase(), a));
  assert.ok(!sameAccountToken(null, a));
});

test('decodeJwsPayload reads the middle part and rejects junk', () => {
  assert.deepEqual(decodeJwsPayload(jws({ a: 1 })), { a: 1 });
  assert.equal(decodeJwsPayload('nope'), null);
  assert.equal(decodeJwsPayload('a.!!!.c'), null);
  assert.equal(decodeJwsPayload(42), null);
});

const appleTx = (extra: object = {}) => ({
  originalTransactionId: '1000',
  productId: 'famotive_premium_monthly',
  expiresDate: NOW + 5 * DAY,
  appAccountToken: 'tok',
  ...extra,
});

test('Apple: free-trial intro offer is a trial', () => {
  const e = entitlementFromApple(1, appleTx({ offerType: 1, offerDiscountType: 'FREE_TRIAL' }), { autoRenewStatus: 1 }, NOW);
  assert.equal(e.state, 'trial');
  assert.equal(e.isTrial, true);
  assert.equal(e.willRenew, true);
  assert.equal(e.expiresAtMs, NOW + 5 * DAY);
  assert.equal(e.checkAfterMs, NOW + 5 * DAY);
  assert.equal(e.accountToken, 'tok');
});

test('Apple: paid, auto-renew off = canceled but still entitled', () => {
  const e = entitlementFromApple(1, appleTx(), { autoRenewStatus: 0 }, NOW);
  assert.equal(e.state, 'canceled');
  assert.equal(e.expiresAtMs, NOW + 5 * DAY);
});

test('Apple: grace period runs to the grace end', () => {
  const e = entitlementFromApple(4, appleTx({ expiresDate: NOW - DAY }), { gracePeriodExpiresDate: NOW + 3 * DAY }, NOW);
  assert.equal(e.state, 'grace');
  assert.equal(e.expiresAtMs, NOW + 3 * DAY);
});

test('Apple: billing retry, expired and refunded are not entitled', () => {
  const retry = entitlementFromApple(3, appleTx({ expiresDate: NOW - DAY }), null, NOW);
  assert.equal(retry.state, 'billing_retry');
  assert.equal(retry.expiresAtMs, null);
  assert.equal(retry.checkAfterMs, NOW + DAY);

  const expired = entitlementFromApple(2, appleTx({ expiresDate: NOW - DAY }), null, NOW);
  assert.equal(expired.state, 'expired');
  assert.equal(expired.checkAfterMs, null);

  const refunded = entitlementFromApple(1, appleTx({ revocationDate: NOW - 1000 }), null, NOW);
  assert.equal(refunded.state, 'revoked');
  assert.equal(refunded.expiresAtMs, null);
});

test('Apple: "active" with a past expiry is treated as expired', () => {
  const e = entitlementFromApple(1, appleTx({ expiresDate: NOW - 1 }), { autoRenewStatus: 1 }, NOW);
  assert.equal(e.state, 'expired');
  assert.equal(e.expiresAtMs, null);
});

test('findAppleItem picks the matching subscription out of the status response', () => {
  const response = {
    data: [
      {
        lastTransactions: [
          { originalTransactionId: '1', status: 2, signedTransactionInfo: jws({ originalTransactionId: '1' }) },
          { originalTransactionId: '2', status: 1, signedTransactionInfo: jws({ originalTransactionId: '2' }) },
        ],
      },
    ],
  };
  assert.equal(findAppleItem(response, '2')?.status, 1);
  assert.equal(findAppleItem(response, null)?.status, 2);
  assert.equal(findAppleItem({}, null), null);
});

const playSub = (state: string, extra: object = {}, line: object = {}) => ({
  subscriptionState: state,
  externalAccountIdentifiers: { obfuscatedExternalAccountId: 'tok' },
  lineItems: [
    {
      productId: 'famotive_premium_monthly',
      expiryTime: new Date(NOW + 6 * DAY).toISOString(),
      autoRenewingPlan: { autoRenewEnabled: true },
      offerDetails: { basePlanId: 'monthly' },
      ...line,
    },
  ],
  ...extra,
});

test('Google: free-trial phase is a trial', () => {
  const e = entitlementFromGoogle(playSub('SUBSCRIPTION_STATE_ACTIVE', {}, { offerPhase: { freeTrial: {} } }), NOW);
  assert.equal(e.state, 'trial');
  assert.equal(e.isTrial, true);
  assert.equal(e.accountToken, 'tok');
  assert.equal(e.expiresAtMs, NOW + 6 * DAY);
});

test('Google: trial detected from the offer id when offerPhase is missing', () => {
  const e = entitlementFromGoogle(
    playSub('SUBSCRIPTION_STATE_ACTIVE', {}, { offerDetails: { basePlanId: 'monthly', offerId: 'free-trial' } }),
    NOW,
  );
  assert.equal(e.state, 'trial');
});

test('Google: active, canceled, grace are entitled; hold/paused/expired are not', () => {
  assert.equal(entitlementFromGoogle(playSub('SUBSCRIPTION_STATE_ACTIVE'), NOW).state, 'active');
  const canceled = entitlementFromGoogle(playSub('SUBSCRIPTION_STATE_CANCELED'), NOW);
  assert.equal(canceled.state, 'canceled');
  assert.equal(canceled.expiresAtMs, NOW + 6 * DAY);
  assert.equal(entitlementFromGoogle(playSub('SUBSCRIPTION_STATE_IN_GRACE_PERIOD'), NOW).state, 'grace');
  for (const [state, expected] of [
    ['SUBSCRIPTION_STATE_ON_HOLD', 'on_hold'],
    ['SUBSCRIPTION_STATE_PAUSED', 'paused'],
    ['SUBSCRIPTION_STATE_EXPIRED', 'expired'],
    ['SUBSCRIPTION_STATE_PENDING', 'pending'],
  ] as const) {
    const e = entitlementFromGoogle(playSub(state), NOW);
    assert.equal(e.state, expected);
    assert.equal(e.expiresAtMs, null);
  }
});

test('subscriptionDocId is deterministic and path-safe', () => {
  const id = subscriptionDocId('android', 'a.b/c-d_e');
  assert.match(id, /^android_[0-9a-f]{40}$/);
  assert.equal(id, subscriptionDocId('android', 'a.b/c-d_e'));
  assert.notEqual(id, subscriptionDocId('ios', 'a.b/c-d_e'));
});

const stored = (extra: Partial<StoredSubscription>): StoredSubscription => ({
  state: 'active',
  expiresAtMs: NOW + DAY,
  isTrial: false,
  willRenew: true,
  productId: 'famotive_premium_monthly',
  platform: 'ios',
  updatedAtMs: NOW,
  ...extra,
});

test('summarize: no subscriptions = none, trial unused', () => {
  const s = summarize([], NOW);
  assert.equal(s.state, 'none');
  assert.equal(s.trialUsed, false);
  assert.equal(s.expiresAtMs, null);
});

test('summarize: longest-running entitled subscription wins', () => {
  const s = summarize(
    [
      stored({ state: 'expired', expiresAtMs: null, updatedAtMs: NOW + 5 }),
      stored({ state: 'trial', isTrial: true, expiresAtMs: NOW + 2 * DAY }),
      stored({ state: 'active', expiresAtMs: NOW + 30 * DAY, productId: 'famotive_premium_yearly' }),
    ],
    NOW,
  );
  assert.equal(s.state, 'active');
  assert.equal(s.productId, 'famotive_premium_yearly');
  assert.equal(s.expiresAtMs, NOW + 30 * DAY);
  assert.equal(s.trialUsed, true);
});

test('summarize: stale "active" record past its end reads as expired', () => {
  const s = summarize([stored({ state: 'active', expiresAtMs: NOW - 1 })], NOW);
  assert.equal(s.state, 'expired');
  assert.equal(s.expiresAtMs, null);
  assert.equal(s.isTrial, false);
});

test('summarize: billing retry is reported as such', () => {
  const s = summarize([stored({ state: 'billing_retry', expiresAtMs: null })], NOW);
  assert.equal(s.state, 'billing_retry');
});

test('householdPremiumUntil follows the admin and ignores the past', () => {
  assert.equal(householdPremiumUntil({ expiresAtMs: NOW + DAY }, NOW), NOW + DAY);
  assert.equal(householdPremiumUntil({ expiresAtMs: NOW - DAY }, NOW), null);
  assert.equal(householdPremiumUntil(null, NOW), null);
});

test('summarize: a complimentary grant with no end gives Premium "forever"', () => {
  const s = summarize([], NOW, { expiresAtMs: null });
  assert.equal(s.state, 'complimentary');
  assert.equal(s.expiresAtMs, COMPLIMENTARY_FOREVER_MS);
  assert.equal(s.trialUsed, false);
  assert.equal(householdPremiumUntil(s, NOW), COMPLIMENTARY_FOREVER_MS);
});

test('summarize: an expired grant falls back to the subscriptions', () => {
  const s = summarize([stored({ state: 'trial', isTrial: true })], NOW, { expiresAtMs: NOW - 1 });
  assert.equal(s.state, 'trial');
  assert.equal(summarize([], NOW, { expiresAtMs: NOW - 1 }).state, 'none');
});

test('summarize: a paid subscription outlasting a dated grant wins', () => {
  const s = summarize([stored({ expiresAtMs: NOW + 30 * DAY })], NOW, { expiresAtMs: NOW + DAY });
  assert.equal(s.state, 'active');
  const g = summarize([stored({ expiresAtMs: NOW + DAY })], NOW, { expiresAtMs: NOW + 30 * DAY });
  assert.equal(g.state, 'complimentary');
  assert.equal(g.trialUsed, true);
});
