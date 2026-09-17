import 'package:flutter/material.dart';

import '../features/auth/screens/forgot_password_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/screens/reset_password_screen.dart';
import '../features/rewards/screens/reward_choose_screen.dart';
import '../features/tasks/screens/create_task_screen.dart';
import '../features/tasks/screens/task_completion_screen.dart';
import '../features/tasks/screens/task_detail_screen.dart';
import '../features/tasks/screens/task_list_screen.dart';
import '../shared/layouts/main_tab_shell.dart';

/// Centralized route names + a single `onGenerateRoute` factory, so
/// navigation reads as `Navigator.pushNamed(context, AppRoutes.taskCreate)`
/// from anywhere in the app instead of screens importing each other
/// directly or building `MaterialPageRoute`s ad hoc.
class AppRoutes {
  AppRoutes._();

  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';

  // Bottom-nav tabs. All 4 build the same persistent `MainTabShell` (just
  // with a different initial tab selected) rather than separate pages, so
  // switching between them never re-navigates - see `MainTabShell` for why.
  static const String home = '/home';
  static const String family = '/family';
  static const String progress = '/progress';
  static const String settings = '/settings';

  // Pushed on top of the tabs
  static const String taskList = '/tasks';
  static const String taskDetail = '/tasks/detail';
  static const String taskCreate = '/tasks/create';
  static const String taskCompletion = '/tasks/completion';
  static const String rewardChoose = '/rewards/choose';

  /// Named routes that build with no required arguments — i.e. the
  /// only ones safe to hand to [onGenerateRoute] sight-unseen from a
  /// platform-provided string (see `FamotiveApp.onGenerateInitialRoutes`,
  /// which uses this to decide whether a cold-start launch route — an
  /// unopened Firebase Auth email-action link, or anything else the OS
  /// might hand us — is safe to route to directly, or should fall back
  /// to the normal home/login route instead).
  static const Set<String> _safeInitialRoutes = {
    login, register, forgotPassword, home, family, progress, settings,
  };

  static bool isSafeInitialRoute(String name) => _safeInitialRoutes.contains(name);

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final args = settings.arguments;

    switch (settings.name) {
      case login:
        return _page(const LoginScreen(), settings);
      case register:
        return _page(const RegisterScreen(), settings);
      case forgotPassword:
        return _page(const ForgotPasswordScreen(), settings);
      case resetPassword:
        final oobCode = args as String;
        return _page(ResetPasswordScreen(oobCode: oobCode), settings);

      case home:
        return _page(const MainTabShell(initialTab: AppTab.home), settings);
      case family:
        return _page(const MainTabShell(initialTab: AppTab.family), settings);
      case progress:
        return _page(const MainTabShell(initialTab: AppTab.progress), settings);
      case AppRoutes.settings:
        return _page(const MainTabShell(initialTab: AppTab.settings), settings);

      case taskList:
        final childId = args as String;
        return _page(TaskListScreen(childId: childId), settings);
      case taskDetail:
        final taskId = args as String;
        return _page(TaskDetailScreen(taskId: taskId), settings);
      case taskCreate:
        final childId = args as String?;
        return _page(CreateTaskScreen(initialChildId: childId), settings);
      case taskCompletion:
        final taskId = args as String;
        return _page(TaskCompletionScreen(taskId: taskId), settings);
      case rewardChoose:
        final childId = args as String;
        return _page(RewardChooseScreen(childId: childId), settings);

      default:
        // Flutter's engine forwards an incoming Universal Link / App
        // Link to Navigator.pushNamed via its native "flutter/navigation"
        // channel any time the app receives one — cold start *or*
        // already running — landing here with the raw link as
        // settings.name, not just via onGenerateInitialRoutes. Rather
        // than depend on DeepLinkService's own app_links-based stream
        // also firing (which may or may not happen depending on
        // platform/plugin registration order), handle a Firebase Auth
        // password-reset link right here too, since this is the one
        // place every delivery path funnels through.
        final resetOobCode = _resetPasswordOobCodeFrom(settings.name);
        if (resetOobCode != null) {
          return _page(ResetPasswordScreen(oobCode: resetOobCode), settings);
        }
        return _page(
          Scaffold(body: Center(child: Text('No route defined for ${settings.name}'))),
          settings,
        );
    }
  }

  /// Pulls the `oobCode` out of a raw Firebase Auth password-reset link
  /// if [routeName] looks like one, or returns null otherwise. Mirrors
  /// `DeepLinkService._modeAndOobCodeFrom` — see its class doc for the
  /// two shapes this has to handle. `routeName` here is usually
  /// scheme/host-less (just the path + query, e.g.
  /// `/__/auth/links?link=...`), so a placeholder base is supplied for
  /// Uri to parse against when needed.
  static String? _resetPasswordOobCodeFrom(String? routeName) {
    if (routeName == null || !routeName.contains('/auth/')) return null;

    final uri = routeName.startsWith('http')
        ? Uri.tryParse(routeName)
        : Uri.tryParse('https://famotive.org$routeName');
    if (uri == null) return null;

    final (mode, oobCode) = _modeAndOobCodeFrom(uri);
    return (mode == 'resetPassword' && oobCode != null && oobCode.isNotEmpty) ? oobCode : null;
  }

  /// Reads `mode`/`oobCode` off [uri], covering both shapes Firebase's
  /// password-reset links show up in in practice:
  ///  - top-level params directly on [uri] — what actually happens when
  ///    the `link=` wrapper value isn't itself percent-encoded, so its
  ///    own `&`/`=` get parsed as [uri]'s *own* query delimiters instead
  ///    of staying inside the `link` value (the case seen in testing);
  ///  - nested inside a `link` query parameter whose value is its own
  ///    URL, when that value *is* properly percent-encoded (the shape
  ///    Firebase's docs describe).
  /// Tries top-level first since that's the shape actually observed.
  static (String?, String?) _modeAndOobCodeFrom(Uri uri) {
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

  static MaterialPageRoute<dynamic> _page(Widget child, RouteSettings settings) {
    return MaterialPageRoute(builder: (_) => child, settings: settings);
  }
}
