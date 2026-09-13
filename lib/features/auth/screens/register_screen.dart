import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/models/user.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_button.dart';
import '../widgets/auth_text_field.dart';

/// Account creation screen, reached from the login screen's "Sign Up"
/// link (`features/auth/screens/register_screen.dart` per the project
/// structure).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  UserRole _role = UserRole.parent;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await context.read<AuthService>().register(
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
            role: _role,
            inviteCode: _role == UserRole.child ? _inviteCodeController.text.trim() : null,
          );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthTextField(
                  controller: _nameController,
<<<<<<< Updated upstream
                  label: 'Full Name',
=======
                  label: 'First and Last Name *',
>>>>>>> Stashed changes
                  icon: Icons.badge_outlined,
                  validator: (v) => Validators.required(v, fieldName: 'Name'),
                ),
                const SizedBox(height: 12),
                AuthTextField(
                  controller: _emailController,
                  label: 'Email *',
                  icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.email,
                ),
                const SizedBox(height: 12),
                AuthTextField(
                  controller: _phoneController,
                  label: 'Phone Number (optional)',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator: Validators.phone,
                  inputFormatters: [
                  PhoneNumberFormatter(),
                  ],
                ),
                const SizedBox(height: 12),
                AuthTextField(
                  controller: _passwordController,
                  label: 'Password *',
                  icon: Icons.lock_outline,
                  obscureText: true,
                  validator: Validators.password,
                ),
                const SizedBox(height: 12),
                AuthTextField(
                  controller: _confirmPasswordController,
<<<<<<< Updated upstream
                  label: 'Confirm Password',
=======
                  label: 'Confirm Your Password *',
>>>>>>> Stashed changes
                  icon: Icons.lock_outline,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  validator: Validators.confirmPassword(() => _passwordController.text),
                ),
                const SizedBox(height: 16),
                Text("I'm signing up as a...", style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<UserRole>(
                  segments: const [
                    ButtonSegment(value: UserRole.parent, label: Text('Parent'), icon: Icon(Icons.escalator_warning)),
                    ButtonSegment(value: UserRole.child, label: Text('Child'), icon: Icon(Icons.child_care)),
                  ],
                  selected: {_role},
                  onSelectionChanged: (selection) => setState(() => _role = selection.first),
                ),
                if (_role == UserRole.child) ...[
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
                    'Ask a parent in your household for their invite code.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                  ),
                ],
                const SizedBox(height: 24),
                AppButton(
                  label: 'Create Account',
                  isLoading: _isSubmitting,
                  onPressed: _handleRegister,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
class PhoneNumberFormatter extends TextInputFormatter {

  @override

  TextEditingValue formatEditUpdate(

    TextEditingValue oldValue,

    TextEditingValue newValue,

  ) {

    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (digits.length > 10) {

      digits = digits.substring(0, 10);

    }

    String formatted = '';

    if (digits.isNotEmpty) {

      if (digits.length <= 3) {

        formatted = '($digits';

      } else if (digits.length <= 6) {

        formatted =

            '(${digits.substring(0, 3)}) ${digits.substring(3)}';

      } else {

        formatted =

            '(${digits.substring(0, 3)}) '

            '${digits.substring(3, 6)}-'

            '${digits.substring(6)}';

      }

    }

    return TextEditingValue(

      text: formatted,

      selection: TextSelection.collapsed(

        offset: formatted.length,

      ),

    );

  }

}