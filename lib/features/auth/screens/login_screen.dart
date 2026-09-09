import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_button.dart';
import '../widgets/auth_text_field.dart';

/// "Welcome/Login" screen — where users sign into the app.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await context.read<AuthService>().login(
            email: _identifierController.text.trim(),
            password: _passwordController.text,
          );
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _handleGoogleSignIn() {
    // TODO: wire up real Google sign-in once Firebase Auth is configured.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Google sign-in is not implemented yet.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Column(
                      children: [
                        const Text('👨‍👩‍👧', style: TextStyle(fontSize: 48)),
                        const SizedBox(height: 8),
                        Text.rich(
                          TextSpan(
                            style: theme.textTheme.headlineSmall,
                            children: [
                              const TextSpan(text: 'Fam'),
                              TextSpan(
                                text: 'otive',
                                style: TextStyle(color: theme.colorScheme.secondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Together. Support. Grow.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  AuthTextField(
                    controller: _identifierController,
                    label: 'Email or Phone',
                    icon: Icons.person_outline,
                    keyboardType: TextInputType.emailAddress,
                    validator: Validators.emailOrPhone,
                  ),
                  const SizedBox(height: 12),
                  AuthTextField(
                    controller: _passwordController,
                    label: 'Password',
                    icon: Icons.lock_outline,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    validator: Validators.password,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        // TODO: implement forgot-password flow.
                      },
                      child: const Text('Forgot Password?'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  AppButton(
                    label: 'Log In',
                    isLoading: _isSubmitting,
                    onPressed: _handleLogin,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or', style: theme.textTheme.bodyMedium),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: 'Continue with Google',
                    variant: AppButtonVariant.secondary,
                    onPressed: _handleGoogleSignIn,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("New to Famotive? "),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pushNamed(AppRoutes.register),
                        child: Text(
                          'Sign Up',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
