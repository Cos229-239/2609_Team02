import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';

import '../../app/routes.dart';
class DeepLinkService {
  DeepLinkService({required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

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
    if (oobCode == null || oobCode.isEmpty) return;

    final String routeName;
    switch (mode) {
      case 'resetPassword':
        routeName = AppRoutes.resetPassword;
        break;
      case 'verifyAndChangeEmail':
        routeName = AppRoutes.confirmEmailChange;
        break;
      default:
        return;
    }

    void navigate() {
      navigatorKey.currentState?.pushNamed(routeName, arguments: oobCode);
    }

    // The very first link (cold start) can arrive before the Navigator
    // exists yet — defer to after the first frame in that case.
    if (navigatorKey.currentState != null) {
      navigate();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => navigate());
    }
  }

  /// The `mode` values this service knows how to route (password reset
  /// and email-change confirmation).
  static const _supportedModes = {'resetPassword', 'verifyAndChangeEmail'};

  
  (String?, String?) _modeAndOobCodeFrom(Uri uri) {
    var mode = uri.queryParameters['mode'];
    var oobCode = uri.queryParameters['oobCode'];
    if (_supportedModes.contains(mode) && oobCode != null && oobCode.isNotEmpty) {
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
