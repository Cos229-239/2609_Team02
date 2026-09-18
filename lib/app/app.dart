import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/services/auth_service.dart';
import '../core/services/database_service.dart';
import 'routes.dart';
import 'theme.dart';

/// Root widget: wires up app-wide state (auth/session + the Firestore
/// household data) and the app's theme + routing.
class FamotiveApp extends StatelessWidget {
  const FamotiveApp({super.key, required this.authService, required this.navigatorKey});

  /// Constructed and given a chance to restore any existing session
  /// (see [AuthService.tryRestoreSession]) before `runApp`, so the initial
  /// route below already reflects whether someone is signed in.
  final AuthService authService;

  /// Shared with [DeepLinkService] (see main.dart) so a password-reset
  /// deep link can push [ResetPasswordScreen] onto whatever's currently
  /// on screen, from outside the widget tree.
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    final homeRouteName = authService.isLoggedIn ? AppRoutes.home : AppRoutes.login;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: authService),
        ChangeNotifierProxyProvider<AuthService, DatabaseService>(
          create: (_) => DatabaseService(),
          update: (_, auth, db) => db!..bindHousehold(auth.currentUser?.householdId),
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        initialRoute: homeRouteName,
        onGenerateRoute: AppRoutes.onGenerateRoute,
        // A Firebase Auth email-action link (password reset, etc.) can
        // arrive as the *platform's* launch route on a cold start —
        // because Flutter feeds the URL that opened the app into
        // onGenerateInitialRoutes before anything else runs — and that
        // isn't one of AppRoutes' named routes, so passing it straight
        // through (as this used to) hits AppRoutes.onGenerateRoute's
        // "No route defined for ..." fallback. We don't try to pattern-
        // match what that raw string looks like (it's varied across
        // platforms in practice) — instead, only ever route directly to
        // it when it's exactly one of our own known, argument-free
        // routes; anything else falls back to the normal home/login
        // route. DeepLinkService independently re-reads that same launch
        // link via the app_links plugin (a separate, non-route-based
        // channel) and pushes ResetPasswordScreen once it's parsed the
        // oobCode — see its getInitialLink() call.
        onGenerateInitialRoutes: (initialRoute) {
          final routeName = AppRoutes.isSafeInitialRoute(initialRoute) ? initialRoute : homeRouteName;
          return [AppRoutes.onGenerateRoute(RouteSettings(name: routeName))];
        },
      ),
    );
  }
}
