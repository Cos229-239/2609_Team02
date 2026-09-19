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
        onGenerateInitialRoutes: (initialRoute) {
          final routeName = AppRoutes.isSafeInitialRoute(initialRoute) ? initialRoute : homeRouteName;
          return [AppRoutes.onGenerateRoute(RouteSettings(name: routeName))];
        },
      ),
    );
  }
}
