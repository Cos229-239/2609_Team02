import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/auth_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/loading_indicator.dart';

enum _ConfirmEmailStatus { verifying, valid, invalid, done }

class ConfirmEmailChangeScreen extends StatefulWidget {
  const ConfirmEmailChangeScreen({super.key, required this.oobCode});

  /// The Firebase Auth out-of-band action code from the confirmation link.
  final String oobCode;

  @override
  State<ConfirmEmailChangeScreen> createState() => _ConfirmEmailChangeScreenState();
}

class _ConfirmEmailChangeScreenState extends State<ConfirmEmailChangeScreen> {
  _ConfirmEmailStatus _status = _ConfirmEmailStatus.verifying;
  String? _newEmail;
  String? _error;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _verifyCode();
  }

  Future<void> _verifyCode() async {
    try {
      final email = await context.read<AuthService>().verifyEmailChangeCode(widget.oobCode);
      if (!mounted) return;
      setState(() {
        _newEmail = email;
        _status = _ConfirmEmailStatus.valid;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _status = _ConfirmEmailStatus.invalid;
      });
    }
  }

  Future<void> _handleConfirm() async {
    setState(() => _isSubmitting = true);
    try {
      await context.read<AuthService>().confirmEmailChange(widget.oobCode, _newEmail!);
      if (!mounted) return;
      setState(() => _status = _ConfirmEmailStatus.done);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Sends the user back into the app — to the signed-in home if this
  /// session is (still) logged in, or to the login screen otherwise (the
  /// link may have been opened on a different device/session).
  void _goBack() {
    final loggedIn = context.read<AuthService>().isLoggedIn;
    Navigator.of(context).pushNamedAndRemoveUntil(
      loggedIn ? AppRoutes.home : AppRoutes.login,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Email Change')),
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
      case _ConfirmEmailStatus.verifying:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: LoadingIndicator(label: 'Checking your link…'),
        );
      case _ConfirmEmailStatus.invalid:
        return _buildInvalidState();
      case _ConfirmEmailStatus.valid:
        return _buildValidState();
      case _ConfirmEmailStatus.done:
        return _buildDoneState();
    }
  }

  Widget _buildInvalidState() {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('⚠️', style: TextStyle(fontSize: AppConstants.emojiIcon3xl), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Text(
          'This link no longer works',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _error ?? 'This confirmation link is invalid or has expired. '
              'Request the email change again from Account Settings.',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        AppButton(label: 'Back to Famotive', onPressed: _goBack),
      ],
    );
  }

  Widget _buildValidState() {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('📧', style: TextStyle(fontSize: AppConstants.emojiIcon2xl), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Text(
          'Confirm your new email',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Change your account email to $_newEmail?',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        AppButton(
          label: 'Confirm Change',
          isLoading: _isSubmitting,
          onPressed: _handleConfirm,
        ),
      ],
    );
  }

  Widget _buildDoneState() {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('✅', style: TextStyle(fontSize: AppConstants.emojiIconXl), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Text(
          'Email updated',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Your account email is now $_newEmail.',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        AppButton(label: 'Back to Famotive', onPressed: _goBack),
      ],
    );
  }
}
