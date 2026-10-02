import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/services/auth_service.dart';
import '../core/services/database_service.dart';
import '../core/services/notification_service.dart';
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

  @override
  Widget build(BuildContext context) {
    final homeRouteName = authService.isLoggedIn ? AppRoutes.home : AppRoutes.login;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: authService),
        Provider<NotificationService?>.value(value: notificationService),
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
      child: MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: scaffoldMessengerKey,
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        initialRoute: homeRouteName,
        onGenerateRoute: AppRoutes.onGenerateRoute,
        onGenerateInitialRoutes: (initialRoute) {
          final routeName = AppRoutes.isSafeInitialRoute(initialRoute) ? initialRoute : homeRouteName;
          return [AppRoutes.onGenerateRoute(RouteSettings(name: routeName))];
        },
      ),
    );
  }
}

void _quietly(Future<void> future) {
  future.catchError((Object e) => debugPrint('Household sync failed: $e'));
}
