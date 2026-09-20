import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_button.dart';
import '../widgets/auth_text_field.dart';

/// Reached from the login screen's "Forgot Password?" link. Collects the
/// account email and asks [AuthService] to send a Firebase Auth password
/// reset email whose link redirects back into this app — see
/// `AuthService.sendPasswordResetEmail` and
/// `lib/core/services/deep_link_service.dart`, which hands the link's
/// `oobCode` off to [ResetPasswordScreen] once it's tapped.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isSubmitting = false;
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await context.read<AuthService>().sendPasswordResetEmail(
            email: _emailController.text.trim(),
          );
      if (!mounted) return;
      setState(() => _emailSent = true);
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _emailSent ? _buildSentState(theme) : _buildFormState(theme),
          ),
        ),
      ),
    );
  }

  Widget _buildFormState(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('🔒', style: TextStyle(fontSize: AppConstants.emojiIcon2xl), textAlign: TextAlign.center,),
          const SizedBox(height: 16),
          Text(
            'Forgot your password?',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            "Enter the email on your account and we'll send you a link to "
            'reset your password right here in the app.',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          AuthTextField(
            controller: _emailController,
            label: 'Email',
            icon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            validator: Validators.email,
            autofillHints: const [AutofillHints.email],
          ),
          const SizedBox(height: 24),
          AppButton(
            label: 'Send Reset Link',
            isLoading: _isSubmitting,
            onPressed: _handleSubmit,
          ),
        ],
      ),
    );
  }

  Widget _buildSentState(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('📬', style: TextStyle(fontSize: AppConstants.emojiIcon2xl), textAlign: TextAlign.center,),
        const SizedBox(height: 16),
        Text(
          'Check your email',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'If an account exists for ${_emailController.text.trim()}, we sent '
          'a reset link to it. Open it on this device to set a new password '
          'right in Famotive.',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        AppButton(
          label: 'Back to Log In',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
