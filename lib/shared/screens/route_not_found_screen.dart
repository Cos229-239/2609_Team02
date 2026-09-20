import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/auth_service.dart';
import '../widgets/app_button.dart';

class RouteNotFoundScreen extends StatelessWidget {
  const RouteNotFoundScreen({super.key, this.attemptedRoute});

  final String? attemptedRoute;

  void _goHome(BuildContext context) {
    final loggedIn = context.read<AuthService>().isLoggedIn;
    Navigator.of(context).pushNamedAndRemoveUntil(
      loggedIn ? AppRoutes.home : AppRoutes.login,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '🙈',
                  style: TextStyle(fontSize: AppConstants.emojiIcon3xl),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  "Oops, sorry about that",
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  "We couldn't find the page you were looking for. "
                  "It may be an old link, or it may have moved.",
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                if (attemptedRoute != null && attemptedRoute!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    attemptedRoute!,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade400),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                AppButton(label: 'Back to Famotive', onPressed: () => _goHome(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
