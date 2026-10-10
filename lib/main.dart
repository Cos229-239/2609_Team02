import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/services/auth_service.dart';
import 'core/services/deep_link_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/theme_controller.dart';
import 'features/onboarding/onboarding_controller.dart';
import 'core/services/premium_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

/// Shared with [DeepLinkService] so a password-reset email link can
/// navigate straight to [ResetPasswordScreen] from outside the widget
/// tree — see lib/app/app.dart and lib/core/services/deep_link_service.dart.
final navigatorKey = GlobalKey<NavigatorState>();

/// Lets [NotificationService] show an in-app banner for push notifications
/// that arrive while the app is in the foreground.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final authService = AuthService();
  await authService.tryRestoreSession();

  // Restore the saved light/dark choice and onboarding progress before the
  // first frame, so there's no flash of the wrong theme and returning users
  // aren't shown the walkthrough again.
  final themeController = ThemeController();
  final onboardingController = OnboardingController();
  await Future.wait([themeController.load(), onboardingController.load()]);

  final notificationService = NotificationService(
    authService: authService,
    navigatorKey: navigatorKey,
    messengerKey: scaffoldMessengerKey,
  );

  // Listens to the store's purchase stream from launch, so renewals and
  // purchases that were interrupted get verified (Famotive Premium).
  final premiumService = PremiumService(authService: authService)..start();

  runApp(FamotiveApp(
    authService: authService,
    navigatorKey: navigatorKey,
    scaffoldMessengerKey: scaffoldMessengerKey,
    notificationService: notificationService,
    themeController: themeController,
    onboardingController: onboardingController,
    premiumService: premiumService,
  ));

  // Started after runApp so DeepLinkService can defer any cold-start link
  // until the Navigator above actually exists (see its _handleUri).
  final deepLinkService = DeepLinkService(navigatorKey: navigatorKey);
  unawaited(deepLinkService.init());

  // Also after runApp, so a notification tap that launched the app can be
  // routed once the Navigator exists. Registers this device's push token
  // whenever someone is signed in.
  unawaited(notificationService.init());
}
