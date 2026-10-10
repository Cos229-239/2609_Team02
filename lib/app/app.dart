import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/services/auth_service.dart';
import '../core/services/database_service.dart';
import '../core/services/notification_service.dart';
import '../core/services/theme_controller.dart';
import '../features/onboarding/onboarding_controller.dart';
import '../core/services/premium_service.dart';
import 'routes.dart';
import 'theme.dart';

/// Root widget: wires up app-wide state (auth/session + the Firestore
/// household data) and the app's theme + routing.
class FamotiveApp extends StatelessWidget {
  const FamotiveApp({
    super.key,
    required this.authService,
    required this.navigatorKey,
    this.scaffoldMessengerKey,
    this.notificationService,
    this.themeController,
    this.onboardingController,
    this.premiumService,
  });

  /// Constructed and given a chance to restore any existing session
  /// (see [AuthService.tryRestoreSession]) before `runApp`, so the initial
  /// route below already reflects whether someone is signed in.
  final AuthService authService;

  /// Shared with [DeepLinkService] (see main.dart) so a password-reset
  /// deep link can push [ResetPasswordScreen] onto whatever's currently
  /// on screen, from outside the widget tree.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Used by [NotificationService] for in-app banners (see main.dart).
  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;

  /// Push notifications; null in tests. Exposed to the Settings screen so
  /// turning notifications back on can re-request permission.
  final NotificationService? notificationService;

  /// Light/dark mode (Settings > Dark Mode). Loaded in main.dart before
  /// `runApp` so the first frame is already in the right theme; tests can
  /// leave it null to get the default (light).
  final ThemeController? themeController;

  /// First-time walkthrough / tutorial progress (see
  /// lib/features/onboarding/). Null in tests: a fresh in-memory one is used.
  final OnboardingController? onboardingController;

  /// Famotive Premium purchases; null in tests.
  final PremiumService? premiumService;

  @override
  Widget build(BuildContext context) {
    final homeRouteName = authService.isLoggedIn ? AppRoutes.home : AppRoutes.login;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: authService),
        Provider<NotificationService?>.value(value: notificationService),
        ChangeNotifierProvider<ThemeController>(
          create: (_) => themeController ?? ThemeController(),
        ),
        ChangeNotifierProvider<OnboardingController>(
          create: (_) => onboardingController ?? (OnboardingController()..load()),
        ),
        ChangeNotifierProvider<PremiumService?>.value(value: premiumService),
        ChangeNotifierProxyProvider<AuthService, DatabaseService>(
          create: (_) => DatabaseService(),
          update: (_, auth, db) => db!
            // Keep the active household valid (e.g. after being removed from
            // one) and tidy up join requests once they're answered.
            ..onActiveHouseholdMissing = ((id) => _quietly(auth.switchHousehold(id)))
            ..onPendingRequestResolved = ((id, {required approved}) =>
                _quietly(auth.forgetPendingHousehold(id, approved: approved)))
            ..bindSession(auth.currentUser),
        ),
      ],
      child: Consumer<ThemeController>(
        builder: (context, appTheme, _) => MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: scaffoldMessengerKey,
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: appTheme.mode,
        initialRoute: homeRouteName,
        onGenerateRoute: AppRoutes.onGenerateRoute,
        onGenerateInitialRoutes: (initialRoute) {
          final routeName = AppRoutes.isSafeInitialRoute(initialRoute) ? initialRoute : homeRouteName;
          return [AppRoutes.onGenerateRoute(RouteSettings(name: routeName))];
        },
      ),
      ),
    );
  }
}

void _quietly(Future<void> future) {
  future.catchError((Object e) => debugPrint('Household sync failed: $e'));
}
