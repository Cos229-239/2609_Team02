import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../constants/app_constants.dart';
import '../models/user.dart';
import 'auth_service.dart';

enum PremiumPeriod { monthly, yearly }

/// One Premium plan as the store sells it.
class PremiumPlan {
  const PremiumPlan({
    required this.product,
    required this.period,
    required this.price,
    required this.freeTrialOffered,
  });

  final ProductDetails product;
  final PremiumPeriod period;

  /// The recurring price, formatted by the store (e.g. "$4.99").
  final String price;

  /// The store offers this account the free trial on this plan. On Android
  /// Play only lists the trial offer to eligible accounts; on iOS the trial
  /// is configured on the product and the App Store applies it if eligible
  /// (the account's own history is in [PremiumStatus.trialUsed]).
  final bool freeTrialOffered;

  String get perPeriod => period == PremiumPeriod.yearly ? '$price/year' : '$price/month';
}

/// Famotive Premium purchases (App Store / Google Play) for parent accounts.
///
/// The app never decides on its own that someone has Premium: every
/// purchase or restore is sent to the `verifyPurchase` Cloud Function, which
/// checks it with the store and writes `users/{uid}.premium` (and the
/// `premiumUntil` of the households they're the admin of). The UI reads those
/// through [AuthService.currentUser] / [DatabaseService.household].
///
/// The 7-day free trial is the subscription's introductory offer in the
/// stores, so the store's own purchase sheet shows the trial terms and
/// handles eligibility.
///
/// Listens to the purchase stream from app start ([start]), because the
/// stores deliver renewals and unfinished purchases there, not just the
/// purchase the user is making right now.
class PremiumService extends ChangeNotifier {
  PremiumService({required AuthService authService, InAppPurchase? iap, FirebaseFunctions? functions})
      : _auth = authService,
        _iapOverride = iap,
        _functionsOverride = functions;

  final AuthService _auth;
  final InAppPurchase? _iapOverride;
  final FirebaseFunctions? _functionsOverride;

  InAppPurchase get _iap => _iapOverride ?? InAppPurchase.instance;
  FirebaseFunctions get _functions => _functionsOverride ?? FirebaseFunctions.instance;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  /// Purchases that arrived while nobody (or a child) was signed in, or
  /// whose verification failed for a temporary reason. Retried when a parent
  /// signs in or on the next purchase update.
  final Map<String, PurchaseDetails> _unverified = {};

  bool _started = false;
  bool storeAvailable = false;
  bool loadingPlans = false;
  List<PremiumPlan> plans = const [];

  /// A purchase or restore is in progress (disable the buttons).
  bool busy = false;

  /// Last problem to show the user, or null.
  String? error;

  /// Last confirmation to show the user (e.g. "Premium is on"), or null.
  String? notice;

  Timer? _restoreTimeout;
  bool _restoreFoundSomething = false;

  /// The UUID a purchase is tagged with (Apple appAccountToken / Google
  /// obfuscatedAccountId) so the server knows which Famotive account bought
  /// it. Must match accountToken() in functions/src/premium/plan.ts.
  static String accountToken(String uid) {
    final b = sha256.convert(utf8.encode('famotive:$uid')).bytes.sublist(0, 16);
    b[6] = (b[6] & 0x0f) | 0x50;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Hooks up the purchase stream. Call once at app start, before anything
  /// else touches in-app purchases.
  void start() {
    if (_started) return;
    _started = true;
    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => debugPrint('PremiumService: purchase stream error: $e'),
    );
    _auth.addListener(_onAuthChanged);
  }

  AppUser? get _parent {
    final user = _auth.currentUser;
    return user != null && user.isParent ? user : null;
  }

  void _onAuthChanged() {
    if (_unverified.isNotEmpty && _parent != null) unawaited(_retryUnverified());
  }

  /// Fetches the plans and prices from the store.
  Future<void> loadPlans() async {
    if (loadingPlans) return;
    loadingPlans = true;
    notifyListeners();
    try {
      storeAvailable = await _iap.isAvailable();
      if (!storeAvailable) {
        plans = const [];
        return;
      }
      final response = await _iap.queryProductDetails(PremiumProducts.ids);
      if (response.error != null) {
        debugPrint('PremiumService: product query failed: ${response.error}');
      }
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('PremiumService: products not set up in the store: ${response.notFoundIDs}');
      }
      plans = _toPlans(response.productDetails);
    } catch (e) {
      debugPrint('PremiumService: could not load plans: $e');
      storeAvailable = false;
      plans = const [];
    } finally {
      loadingPlans = false;
      notifyListeners();
    }
  }

  /// One plan per product. Google Play lists a product once per base plan
  /// and once per offer the account is eligible for; prefer the free-trial
  /// offer when it's there.
  List<PremiumPlan> _toPlans(List<ProductDetails> details) {
    final byId = <String, PremiumPlan>{};
    for (final d in details) {
      final period = d.id == PremiumProducts.yearly ? PremiumPeriod.yearly : PremiumPeriod.monthly;
      PremiumPlan plan;
      if (d is GooglePlayProductDetails) {
        final offers = d.productDetails.subscriptionOfferDetails;
        final index = d.subscriptionIndex;
        if (offers == null || index == null || index >= offers.length) continue;
        final phases = offers[index].pricingPhases;
        if (phases.isEmpty) continue;
        plan = PremiumPlan(
          product: d,
          period: period,
          price: phases.last.formattedPrice,
          freeTrialOffered: phases.any((p) => p.priceAmountMicros == 0),
        );
      } else {
        plan = PremiumPlan(product: d, period: period, price: d.price, freeTrialOffered: true);
      }
      final existing = byId[d.id];
      if (existing == null || (plan.freeTrialOffered && !existing.freeTrialOffered)) byId[d.id] = plan;
    }
    final list = byId.values.toList()..sort((a, b) => a.period.index.compareTo(b.period.index));
    return list;
  }

  /// Opens the store's purchase sheet. The result arrives on the purchase
  /// stream.
  Future<void> buy(PremiumPlan plan) async {
    final parent = _parent;
    if (parent == null || busy) return;
    _setBusy(true);
    try {
      final started = await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(
          productDetails: plan.product,
          applicationUserName: accountToken(parent.id),
        ),
      );
      if (!started) _fail("Couldn't open the store. Please try again.");
    } catch (e) {
      debugPrint('PremiumService: buy failed: $e');
      _fail(_storeErrorMessage(e));
    }
  }

  /// Asks the store for this store account's existing purchases.
  Future<void> restore() async {
    final parent = _parent;
    if (parent == null || busy) return;
    _setBusy(true);
    _restoreFoundSomething = false;
    try {
      await _iap.restorePurchases(applicationUserName: accountToken(parent.id));
      // Restored purchases arrive on the stream; if none do, say so.
      _restoreTimeout?.cancel();
      _restoreTimeout = Timer(const Duration(seconds: 4), () {
        if (!busy || _restoreFoundSomething) return;
        busy = false;
        notice = 'No Premium subscription found for this ${_storeName()} account.';
        notifyListeners();
      });
    } catch (e) {
      debugPrint('PremiumService: restore failed: $e');
      _fail(_storeErrorMessage(e));
    }
  }

  void clearMessages() {
    if (error == null && notice == null) return;
    error = null;
    notice = null;
    notifyListeners();
  }

  // --- Purchase stream ------------------------------------------------------

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    final toVerify = <PurchaseDetails>[];
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          // e.g. Ask to Buy, or a slow payment method. Nothing to do yet.
          notice = 'Your purchase is pending. Premium turns on once the store confirms it.';
          busy = false;
        case PurchaseStatus.canceled:
          busy = false;
          await _complete(p);
        case PurchaseStatus.error:
          busy = false;
          error = p.error?.message ?? 'The purchase did not go through.';
          await _complete(p);
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (PremiumProducts.ids.contains(p.productID)) {
            _restoreFoundSomething = true;
            toVerify.add(p);
          } else {
            await _complete(p);
          }
      }
    }
    notifyListeners();
    if (toVerify.isNotEmpty) await _verifyBatch(toVerify);
  }

  /// On iOS a restore can return every past transaction; the server looks
  /// up the subscription's current state from any one of them, so only the
  /// newest is sent and all of them are then finished. On Android each
  /// purchase token is its own subscription, so each is sent.
  Future<void> _verifyBatch(List<PurchaseDetails> batch) async {
    batch.sort((a, b) => _date(b).compareTo(_date(a)));
    final groups = batch.first is GooglePlayPurchaseDetails
        ? [for (final p in batch) [p]]
        : [batch];
    for (final group in groups) {
      final ok = await _verify(group.first);
      for (final p in group) {
        if (ok) {
          _unverified.remove(_key(p));
          await _complete(p);
        } else {
          _unverified[_key(p)] = p;
        }
      }
    }
    busy = false;
    notifyListeners();
  }

  bool _retrying = false;

  Future<void> _retryUnverified() async {
    if (_unverified.isEmpty || _retrying) return;
    _retrying = true;
    try {
      await _verifyBatch(_unverified.values.toList());
    } finally {
      _retrying = false;
    }
  }

  /// Sends one purchase to the server. Returns true when it's settled (on,
  /// or definitely not ours), false when it should be retried later.
  Future<bool> _verify(PurchaseDetails p) async {
    if (_parent == null) return false; // wait for a parent to sign in
    final android = p is GooglePlayPurchaseDetails || (!kIsWeb && Platform.isAndroid);
    final data = android
        ? {'platform': 'android', 'purchaseToken': p.verificationData.serverVerificationData}
        : {'platform': 'ios', 'transactionId': p.purchaseID};
    try {
      final result = await _functions.httpsCallable('verifyPurchase').call<Object?>(data);
      final response = result.data;
      final state = response is Map ? response['state'] : null;
      if (state == 'trial') {
        notice = "Your ${AppConstants.premiumTrialDays}-day free trial has started. Photo proof is on!";
      } else if (state == 'active' || state == 'canceled' || state == 'grace') {
        notice = 'Premium is on. Photo proof is unlocked.';
      } else {
        notice = 'That subscription is no longer active.';
      }
      error = null;
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('PremiumService: verifyPurchase failed: ${e.code} ${e.message}');
      final permanent = e.code == 'failed-precondition' ||
          e.code == 'invalid-argument' ||
          e.code == 'not-found' ||
          e.code == 'permission-denied';
      // "Not configured" is a server setup problem, not the purchase's fault:
      // keep it to retry once that's fixed.
      final notConfigured = e.message?.contains('not configured') ?? false;
      error = e.message ?? 'Could not confirm your purchase.';
      return permanent && !notConfigured;
    } catch (e) {
      debugPrint('PremiumService: verifyPurchase failed: $e');
      error = "Couldn't confirm your purchase yet. We'll try again shortly.";
      return false;
    }
  }

  Future<void> _complete(PurchaseDetails p) async {
    if (!p.pendingCompletePurchase) return;
    try {
      await _iap.completePurchase(p);
    } catch (e) {
      debugPrint('PremiumService: completePurchase failed: $e');
    }
  }

  // --- Helpers --------------------------------------------------------------

  static String _key(PurchaseDetails p) =>
      p.purchaseID ?? p.verificationData.serverVerificationData;

  static int _date(PurchaseDetails p) => int.tryParse(p.transactionDate ?? '') ?? 0;

  void _setBusy(bool value) {
    busy = value;
    error = null;
    notice = null;
    notifyListeners();
  }

  void _fail(String message) {
    busy = false;
    error = message;
    notifyListeners();
  }

  static String _storeName() => !kIsWeb && Platform.isAndroid ? 'Google Play' : 'App Store';

  static String _storeErrorMessage(Object e) {
    final text = e.toString();
    if (text.contains('already') && text.contains('own')) {
      return 'You already have this subscription. Try "Restore Purchases".';
    }
    return 'Something went wrong with the store. Please try again.';
  }

  /// Where the user manages / cancels their subscription.
  static Uri manageSubscriptionsUri({String? productId}) {
    if (!kIsWeb && Platform.isAndroid) {
      return Uri.parse(AppConstants.googleManageSubscriptionsUrl).replace(queryParameters: {
        'package': AppConstants.androidPackageName,
        'sku': ?productId,
      });
    }
    return Uri.parse(AppConstants.appleManageSubscriptionsUrl);
  }

  @override
  void dispose() {
    _restoreTimeout?.cancel();
    _auth.removeListener(_onAuthChanged);
    unawaited(_purchaseSub?.cancel());
    super.dispose();
  }
}
