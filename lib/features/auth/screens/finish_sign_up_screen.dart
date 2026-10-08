import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/models/user.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/utils/legal_links.dart';
import '../../../shared/widgets/app_button.dart';
import '../widgets/auth_text_field.dart';
import 'register_screen.dart' show PhoneNumberFormatter;

/// Shown the first time someone signs in with Google/Apple: the account
/// exists in Firebase Auth but has no Famotive profile yet. Collects the
/// same choices as RegisterScreen (minus email/password) and then calls
/// [AuthService.completeSocialSignUp]. Backing out deletes the unfinished
/// account and signs out.
class FinishSignUpScreen extends StatefulWidget {
  const FinishSignUpScreen({super.key, this.suggestedName, this.email});

  final String? suggestedName;
  final String? email;

  @override
  State<FinishSignUpScreen> createState() => _FinishSignUpScreenState();
}

class _FinishSignUpScreenState extends State<FinishSignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.suggestedName ?? '');
  final _phoneController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  UserRole _role = UserRole.parent;
  bool _joinExisting = false;
  bool _isSubmitting = false;
  bool _finished = false;
  bool _leaving = false;

  bool get _usesInviteCode => _role == UserRole.child || _joinExisting;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final phone = _phoneController.text.trim();
      await context.read<AuthService>().completeSocialSignUp(
            name: _nameController.text.trim(),
            role: _role,
            phoneNumber: phone.isEmpty ? null : phone,
            inviteCode: _usesInviteCode ? _inviteCodeController.text.trim() : null,
          );
      _finished = true;
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Backing out: remove the half-made account and sign out *before*
  /// popping, so the previous screen never sees a stale session (and a quick
  /// second sign-in can't be signed out by a cleanup still in flight).
  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      await context.read<AuthService>().cancelSocialSignUp();
    } catch (e) {
      debugPrint('Cancel sign-up failed: $e');
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600);

    return PopScope(
      // Leaving without finishing removes the half-made account; the pop
      // waits for that cleanup (see [_leave]).
      canPop: _finished,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Finish Signing Up'),
          bottom: _leaving
              ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
              : null,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Almost there!', style: theme.textTheme.headlineSmall),
                  if (widget.email != null && widget.email!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Signed in as ${widget.email}', style: hint),
                  ],
                  const SizedBox(height: 20),
                  AuthTextField(
                    controller: _nameController,
                    label: 'First and Last Name *',
                    icon: Icons.badge_outlined,
                    validator: (v) => Validators.required(v, fieldName: 'Name'),
                  ),
                  const SizedBox(height: 12),
                  AuthTextField(
                    controller: _phoneController,
                    label: 'Phone Number (optional)',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: Validators.phone,
                    inputFormatters: [PhoneNumberFormatter()],
                  ),
                  const SizedBox(height: 16),
                  Text("I'm signing up as a...", style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SegmentedButton<UserRole>(
                    segments: const [
                      ButtonSegment(value: UserRole.parent, label: Text('Parent'), icon: Icon(Icons.escalator_warning)),
                      ButtonSegment(value: UserRole.child, label: Text('Child'), icon: Icon(Icons.child_care)),
                    ],
                    selected: {_role},
                    onSelectionChanged: (selection) => setState(() => _role = selection.first),
                  ),
                  if (_role == UserRole.parent) ...[
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Start a household'), icon: Icon(Icons.add_home_outlined)),
                        ButtonSegment(value: true, label: Text('Join one'), icon: Icon(Icons.group_add_outlined)),
                      ],
                      selected: {_joinExisting},
                      onSelectionChanged: (selection) => setState(() => _joinExisting = selection.first),
                    ),
                    if (!_joinExisting) ...[
                      const SizedBox(height: 4),
                      Text("You'll be the household's admin: you approve anyone who asks to join.", style: hint),
                    ],
                  ],
                  if (_usesInviteCode) ...[
                    const SizedBox(height: 12),
                    AuthTextField(
                      controller: _inviteCodeController,
                      label: 'Family Invite Code',
                      icon: Icons.groups_outlined,
                      textInputAction: TextInputAction.done,
                      validator: (v) => Validators.required(v, fieldName: 'Invite code'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Ask a parent in your household for their invite code. The household's "
                      'admin approves your request before you can see it.',
                      style: hint,
                    ),
                  ],
                  const SizedBox(height: 24),
                  AppButton(label: 'Create Account', isLoading: _isSubmitting, onPressed: _leaving ? null : _submit),
                  const SizedBox(height: 12),
                  const LegalFooter(prefix: 'By creating an account, you agree to our'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
