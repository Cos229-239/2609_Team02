/**
 * Talking to the stores (network only; the interpretation is in ./plan.ts).
 *
 * Apple: App Store Server API, authenticated with an In-App Purchase key
 *   (App Store Connect > Users and Access > Integrations > In-App Purchase).
 *   Responses come straight from Apple over TLS with our own credentials, so
 *   their signed fields are decoded without re-verifying the signature.
 * Google: Play Developer API, authenticated as the functions' service account
 *   (token from the metadata server). That account must be invited in Play
 *   Console with "View financial data" + "Manage orders and subscriptions".
 */
import { createPrivateKey, sign } from 'node:crypto';

export class StoreError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code?: number,
  ) {
    super(message);
  }
}

// --- Apple ------------------------------------------------------------------

export interface AppleConfig {
  bundleId: string;
  issuerId: string;
  keyId: string;
  /** Contents of the .p8 key file. */
  privateKey: string;
}

const APPLE_HOSTS = {
  Production: 'https://api.storekit.itunes.apple.com',
  Sandbox: 'https://api.storekit-sandbox.itunes.apple.com',
} as const;
export type AppleEnvironment = keyof typeof APPLE_HOSTS;

/** App Store Server API error code for "no such transaction (in this environment)". */
const APPLE_TRANSACTION_NOT_FOUND = new Set([4040010, 4040005]);
const APPLE_INVALID_TRANSACTION_ID = 4000006;

function appleJwt(cfg: AppleConfig): string {
  const now = Math.floor(Date.now() / 1000);
  const enc = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const head = enc({ alg: 'ES256', kid: cfg.keyId, typ: 'JWT' });
  const body = enc({ iss: cfg.issuerId, iat: now, exp: now + 20 * 60, aud: 'appstoreconnect-v1', bid: cfg.bundleId });
  // Keys pasted into Secret Manager sometimes lose their line breaks.
  const pem = cfg.privateKey.includes('\n') ? cfg.privateKey : cfg.privateKey.replace(/\\n/g, '\n');
  const sig = sign('sha256', Buffer.from(`${head}.${body}`), {
    key: createPrivateKey(pem),
    dsaEncoding: 'ieee-p1363',
  }).toString('base64url');
  return `${head}.${body}.${sig}`;
}

async function appleGet(cfg: AppleConfig, env: AppleEnvironment, path: string): Promise<unknown> {
  const res = await fetch(`${APPLE_HOSTS[env]}${path}`, {
    headers: { Authorization: `Bearer ${appleJwt(cfg)}` },
  });
  const text = await res.text();
  let json: unknown = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    /* not JSON */
  }
  if (!res.ok) {
    const code = (json as { errorCode?: number } | null)?.errorCode;
    throw new StoreError(`App Store Server API ${res.status} ${code ?? ''} ${text.slice(0, 200)}`, res.status, code);
  }
  return json;
}

/**
 * Get All Subscription Statuses for any transaction id of a subscription.
 * Tries Production, then Sandbox (TestFlight / sandbox testers), unless
 * [env] is known.
 */
export async function appleSubscriptionStatuses(
  cfg: AppleConfig,
  transactionId: string,
  env?: AppleEnvironment,
): Promise<{ env: AppleEnvironment; response: unknown }> {
  if (!/^\d{1,30}$/.test(transactionId)) {
    throw new StoreError('Invalid transaction id', 400, APPLE_INVALID_TRANSACTION_ID);
  }
  const path = `/inApps/v1/subscriptions/${transactionId}`;
  const order: AppleEnvironment[] = env ? [env] : ['Production', 'Sandbox'];
  let last: unknown;
  for (const e of order) {
    try {
      return { env: e, response: await appleGet(cfg, e, path) };
    } catch (err) {
      last = err;
      const notFound = err instanceof StoreError && (err.status === 404 || APPLE_TRANSACTION_NOT_FOUND.has(err.code ?? -1));
      if (!notFound) throw err;
    }
  }
  throw last;
}

// --- Google -----------------------------------------------------------------

const PLAY_API = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications';
const METADATA_TOKEN =
  'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token' +
  '?scopes=https://www.googleapis.com/auth/androidpublisher';

let cachedToken: { value: string; expiresAt: number } | null = null;

async function playToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) return cachedToken.value;
  const res = await fetch(METADATA_TOKEN, { headers: { 'Metadata-Flavor': 'Google' } });
  if (!res.ok) throw new StoreError(`Metadata token ${res.status}`, res.status);
  const body = (await res.json()) as { access_token: string; expires_in: number };
  cachedToken = { value: body.access_token, expiresAt: Date.now() + body.expires_in * 1000 };
  return body.access_token;
}

async function playFetch(url: string, init?: RequestInit): Promise<unknown> {
  const res = await fetch(url, {
    ...init,
    headers: { Authorization: `Bearer ${await playToken()}`, 'Content-Type': 'application/json', ...(init?.headers ?? {}) },
  });
  const text = await res.text();
  if (!res.ok) throw new StoreError(`Play Developer API ${res.status} ${text.slice(0, 300)}`, res.status);
  return text ? JSON.parse(text) : {};
}

/** purchases.subscriptionsv2.get */
export async function playSubscription(packageName: string, purchaseToken: string): Promise<Record<string, unknown>> {
  const url = `${PLAY_API}/${encodeURIComponent(packageName)}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
  return (await playFetch(url)) as Record<string, unknown>;
}

/**
 * Acknowledges a subscription purchase (Google refunds anything left
 * unacknowledged for 3 days). The app's completePurchase does this too; this
 * is the backstop if the app is closed before it gets there.
 */
export async function playAcknowledge(packageName: string, productId: string, purchaseToken: string): Promise<void> {
  const url =
    `${PLAY_API}/${encodeURIComponent(packageName)}/purchases/subscriptions/` +
    `${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`;
  await playFetch(url, { method: 'POST', body: '{}' });
}
