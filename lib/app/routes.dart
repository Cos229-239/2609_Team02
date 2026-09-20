import 'package:flutter/material.dart';

import '../features/auth/screens/forgot_password_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/screens/reset_password_screen.dart';
import '../features/auth/screens/confirm_email_change_screen.dart';
import '../features/profile/screens/account_settings_screen.dart';
import '../features/profile/screens/notifications_settings_screen.dart';
import '../features/rewards/screens/reward_choose_screen.dart';
import '../features/tasks/screens/create_task_screen.dart';
import '../features/tasks/screens/task_completion_screen.dart';
import '../features/tasks/screens/task_detail_screen.dart';
import '../features/tasks/screens/task_list_screen.dart';
import '../shared/layouts/main_tab_shell.dart';
import '../shared/screens/route_not_found_screen.dart';

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
  static const String confirmEmailChange = '/confirm-email-change';

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

  // Settings sub-screens, pushed from the Settings tab.
  static const String accountSettings = '/settings/account';
  static const String notificationSettings = '/settings/notifications';

 
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
      case confirmEmailChange:
        final oobCode = args as String;
        return _page(ConfirmEmailChangeScreen(oobCode: oobCode), settings);

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

      case accountSettings:
        return _page(const AccountSettingsScreen(), settings);
      case notificationSettings:
        return _page(const NotificationsSettingsScreen(), settings);

      default:
        final (authMode, authOobCode) = _authActionFrom(settings.name);
        if (authOobCode != null && authOobCode.isNotEmpty) {
          if (authMode == 'resetPassword') {
            return _page(ResetPasswordScreen(oobCode: authOobCode), settings);
          }
          if (authMode == 'verifyAndChangeEmail') {
            return _page(ConfirmEmailChangeScreen(oobCode: authOobCode), settings);
          }
        }
        return _page(
          RouteNotFoundScreen(attemptedRoute: settings.name),
          settings,
        );
    }
  }

  static (String?, String?) _authActionFrom(String? routeName) {
    if (routeName == null || !routeName.contains('/auth/')) return (null, null);

    final uri = routeName.startsWith('http')
        ? Uri.tryParse(routeName)
        : Uri.tryParse('https://famotive.org$routeName');
    if (uri == null) return (null, null);

    return _modeAndOobCodeFrom(uri);
  }

  static const _supportedModes = {'resetPassword', 'verifyAndChangeEmail'};

  static (String?, String?) _modeAndOobCodeFrom(Uri uri) {
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

  static MaterialPageRoute<dynamic> _page(Widget child, RouteSettings settings) {
    return MaterialPageRoute(builder: (_) => child, settings: settings);
  }
}
