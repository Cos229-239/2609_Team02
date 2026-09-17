import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';

import '../../app/routes.dart';

/// Listens for the incoming deep link Firebase Auth's password-reset
/// emails open and routes the `oobCode` into [ResetPasswordScreen].
///
/// Firebase Dynamic Links (the service this used to go through) was shut
/// down in Aug 2025; the replacement is a plain Android App Link / iOS
/// Universal Link that the OS hands straight to this app when it's
/// installed and famotive.org's domain is verified. See the intent-filter
/// in `android/app/src/main/AndroidManifest.xml` and the associated-
/// domains entitlement in `ios/Runner/Runner.entitlements`, and
/// `docs/password-reset-setup.md` for the Firebase/DNS console steps that
/// make the domain actually verify.
///
/// The link Firebase actually sends looks like `famotive.org/__/auth/
/// links` followed by a `link` query parameter, whose value is meant to
/// be a URL-encoded `firebaseapp.com/__/auth/action` link carrying the
/// real `mode`, `oobCode` and `continueUrl` params. In practice that
/// `link` value isn't always percent-encoded, so its own `&`/`=` end up
/// parsed as this URI's *own* top-level query params instead of staying
/// nested — see [_modeAndOobCodeFrom], which checks both shapes.
class DeepLinkService {
  DeepLinkService({required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  /// Starts listening. Safe to call once, after `runApp` — call it without
  /// awaiting it from `main()` (a cold-start link, if any, is only handled
  /// once the first frame is up; see [_handleUri]).
  Future<void> init() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) _handleUri(initialUri);
    } catch (_) {
      // No initial link, or the platform channel wasn't ready — ignore,
      // there's nothing to recover from a cold-start link failure.
    }

    _subscription = _appLinks.uriLinkStream.listen(_handleUri, onError: (_) {});
  }

  void dispose() {
    _subscription?.cancel();
  }

  void _handleUri(Uri uri) {
    final (mode, oobCode) = _modeAndOobCodeFrom(uri);
    if (mode != 'resetPassword' || oobCode == null || oobCode.isEmpty) return;

    void navigate() {
      navigatorKey.currentState?.pushNamed(AppRoutes.resetPassword, arguments: oobCode);
    }

    // The very first link (cold start) can arrive before the Navigator
    // exists yet — defer to after the first frame in that case.
    if (navigatorKey.currentState != null) {
      navigate();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => navigate());
    }
  }

  /// Reads `mode`/`oobCode` off [uri], covering both shapes Firebase's
  /// password-reset links show up in in practice — see the class doc.
  /// Tries top-level params first (the shape actually observed in
  /// testing), then falls back to unwrapping a `link` query parameter's
  /// value as its own URI (the properly-encoded shape).
  (String?, String?) _modeAndOobCodeFrom(Uri uri) {
    var mode = uri.queryParameters['mode'];
    var oobCode = uri.queryParameters['oobCode'];
    if (mode == 'resetPassword' && oobCode != null && oobCode.isNotEmpty) {
      return (mode, oobCode);
    }

    final inner = uri.queryParameters['link'];
    if (inner != null && inner.isNotEmpty) {
      final innerUri = Uri.tryParse(inner);
      mode = innerUri?.queryParameters['mode'];
      oobCode = innerUri?.queryParameters['oobCode'];
    }
    return (mode, oobCode);
  }
}
