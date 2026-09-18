import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/services/auth_service.dart';
import 'core/services/deep_link_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

/// Shared with [DeepLinkService] so a password-reset email link can
/// navigate straight to [ResetPasswordScreen] from outside the widget
/// tree — see lib/app/app.dart and lib/core/services/deep_link_service.dart.
final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final authService = AuthService();
  await authService.tryRestoreSession();

  runApp(FamotiveApp(authService: authService, navigatorKey: navigatorKey));

  // Started after runApp so DeepLinkService can defer any cold-start link
  // until the Navigator above actually exists (see its _handleUri).
  final deepLinkService = DeepLinkService(navigatorKey: navigatorKey);
  unawaited(deepLinkService.init());
}
