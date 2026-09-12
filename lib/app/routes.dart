import 'package:flutter/material.dart';

import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
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

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final args = settings.arguments;

    switch (settings.name) {
      case login:
        return _page(const LoginScreen(), settings);
      case register:
        return _page(const RegisterScreen(), settings);

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
        return _page(
          Scaffold(body: Center(child: Text('No route defined for ${settings.name}'))),
          settings,
        );
    }
  }

  static MaterialPageRoute<dynamic> _page(Widget child, RouteSettings settings) {
    return MaterialPageRoute(builder: (_) => child, settings: settings);
  }
}
