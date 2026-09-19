import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../widgets/auth_text_field.dart';

enum _ResetStatus { verifying, valid, invalid, done }

/// Reached by tapping the link in a Firebase Auth password-reset email.
/// `lib/core/services/deep_link_service.dart` intercepts the incoming
/// `https://famotive.org/__/auth/links?...&oobCode=...` link (opened
/// directly in-app via Android App Links / iOS Universal Links) and pushes
/// this screen with that `oobCode`.
///
/// The code is verified up front (it may be expired, already used, or
/// tampered with) before showing the "choose a new password" form, so
/// users get a clear message instead of a confusing failure after typing
/// a new password.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.oobCode});

  /// The Firebase Auth out-of-band action code from the reset link.
  final String oobCode;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _ResetStatus _status = _ResetStatus.verifying;
  String? _email;
  String? _error;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _verifyCode();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    try {
      final email = await context.read<AuthService>().verifyPasswordResetCode(widget.oobCode);
      if (!mounted) return;
      setState(() {
        _email = email;
        _status = _ResetStatus.valid;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _status = _ResetStatus.invalid;
      });
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await context.read<AuthService>().confirmPasswordReset(
            oobCode: widget.oobCode,
            newPassword: _passwordController.text,
          );
      if (!mounted) return;
      setState(() => _status = _ResetStatus.done);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case _ResetStatus.verifying:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: LoadingIndicator(label: 'Checking your link…'),
        );
      case _ResetStatus.invalid:
        return _buildInvalidState();
      case _ResetStatus.valid:
        return _buildFormState();
      case _ResetStatus.done:
        return _buildDoneState();
    }
  }

  Widget _buildInvalidState() {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('⚠️', style: TextStyle(fontSize: AppConstants.emojiIcon3xl), textAlign: TextAlign.center,),
        const SizedBox(height: 16),
        Text(
          'This link no longer works',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _error ?? 'This reset link is invalid or has expired.',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        AppButton(
          label: 'Request a New Link',
          onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.forgotPassword),
        ),
      ],
    );
  }

  Widget _buildFormState() {
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('🔑', style: TextStyle(fontSize: AppConstants.emojiIconXl), textAlign: TextAlign.center,),
          const SizedBox(height: 16),
          Text(
            'Choose a new password',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          if (_email != null) ...[
            const SizedBox(height: 8),
            Text(
              'for $_email',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 32),
          AuthTextField(
            controller: _passwordController,
            label: 'New Password',
            icon: Icons.lock_outline,
            obscureText: true,
            validator: Validators.password,
          ),
          const SizedBox(height: 12),
          AuthTextField(
            controller: _confirmController,
            label: 'Confirm New Password',
            icon: Icons.lock_outline,
            obscureText: true,
            textInputAction: TextInputAction.done,
            validator: Validators.confirmPassword(() => _passwordController.text),
          ),
          const SizedBox(height: 24),
          AppButton(
            label: 'Reset Password',
            isLoading: _isSubmitting,
            onPressed: _handleSubmit,
          ),
        ],
      ),
    );
  }

  Widget _buildDoneState() {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('✅', style: TextStyle(fontSize: AppConstants.emojiIconXl), textAlign: TextAlign.center,),
        const SizedBox(height: 16),
        Text(
          'Password updated',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Your password has been reset. Log in with your new password.',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        AppButton(
          label: 'Back to Log In',
          onPressed: () => Navigator.of(context)
              .pushNamedAndRemoveUntil(AppRoutes.login, (route) => false),
        ),
      ],
    );
  }
}
