import 'package:cloud_firestore/cloud_firestore.dart';

/// An account's Famotive Premium subscription, as summarized by the server in
/// `users/{uid}.premium` (functions/src/premium). Read-only in the app: only
/// Cloud Functions write it, after checking the purchase with the store.
///
/// Premium belongs to the account. The households this account is the admin
/// of get the Premium features (see [Household.hasPremium]).
class PremiumStatus {
  const PremiumStatus({
    this.state = PremiumState.none,
    this.expiresAt,
    this.isTrial = false,
    this.willRenew = false,
    this.trialUsed = false,
    this.productId,
    this.platform,
  });

  static const PremiumStatus none = PremiumStatus();

  final PremiumState state;

  /// When access ends (the trial / billing period / grace period end), or
  /// null when not subscribed.
  final DateTime? expiresAt;

  /// In the free trial.
  final bool isTrial;

  /// Auto-renew is on (false once cancelled; access lasts until [expiresAt]).
  final bool willRenew;

  /// This account has subscribed before, so the stores won't offer the free
  /// trial again.
  final bool trialUsed;

  final String? productId;

  /// 'ios' or 'android': where the subscription is managed.
  final String? platform;

  bool get isActive => expiresAt != null && expiresAt!.isAfter(DateTime.now());

  /// The last renewal failed and the store is retrying (no access meanwhile).
  bool get hasPaymentProblem =>
      state == PremiumState.billingRetry || state == PremiumState.onHold;

  factory PremiumStatus.fromMap(Object? raw) {
    if (raw is! Map) return none;
    final expires = raw['expiresAt'];
    return PremiumStatus(
      state: PremiumState.parse(raw['state']),
      expiresAt: expires is Timestamp ? expires.toDate() : null,
      isTrial: raw['isTrial'] == true,
      willRenew: raw['willRenew'] == true,
      trialUsed: raw['trialUsed'] == true,
      productId: raw['productId'] as String?,
      platform: raw['platform'] as String?,
    );
  }
}

/// Mirrors PremiumState in functions/src/premium/plan.ts.
enum PremiumState {
  none('none'),
  /// Granted by hand (test / staff accounts), not bought: `premiumGrants/{uid}`.
  complimentary('complimentary'),
  trial('trial'),
  active('active'),
  canceled('canceled'),
  grace('grace'),
  billingRetry('billing_retry'),
  onHold('on_hold'),
  paused('paused'),
  pending('pending'),
  expired('expired'),
  revoked('revoked'),
  replaced('replaced');

  const PremiumState(this.wire);

  final String wire;

  static PremiumState parse(Object? value) =>
      PremiumState.values.firstWhere((s) => s.wire == value, orElse: () => PremiumState.none);
}
