import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../auth/screens/register_screen.dart' show PhoneNumberFormatter;
import '../../auth/widgets/auth_text_field.dart';
import '../widgets/avatar_picker_sheet.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/current_password_prompt.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late String _avatarEmoji;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthService>().currentUser;
    _nameController = TextEditingController(text: user?.name ?? '');
    _ageController = TextEditingController(text: user?.age?.toString() ?? '');
    _phoneController = TextEditingController(text: user?.phoneNumber ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _avatarEmoji = user?.avatarEmoji ?? '🙂';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final selected = await AvatarPickerSheet.show(context, selected: _avatarEmoji);
    if (selected != null && mounted) {
      setState(() => _avatarEmoji = selected);
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthService>();
    final currentUser = auth.currentUser;
    if (currentUser == null) return;

    final newEmail = _emailController.text.trim();
    final emailChanged = newEmail != currentUser.email;

    String? currentPassword;
    if (emailChanged) {
      currentPassword = await CurrentPasswordPrompt.show(
        context,
        message: 'Enter your current password to change your email address.',
      );
      if (currentPassword == null || !mounted) return; // cancelled
    }

    setState(() => _isSaving = true);
    try {
      final ageText = _ageController.text.trim();
      final phoneText = _phoneController.text.trim();

      await auth.updateProfile(
        name: _nameController.text.trim(),
        avatarEmoji: _avatarEmoji,
        age: ageText.isEmpty ? null : int.tryParse(ageText),
        phoneNumber: phoneText.isEmpty ? null : phoneText,
      );

      if (emailChanged) {
        await auth.updateEmail(newEmail: newEmail, currentPassword: currentPassword!);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            emailChanged
                ? 'Profile saved. Tap the confirmation link we sent to $newEmail to finish the change.'
                : 'Profile saved.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthService>().currentUser;

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('Not signed in.')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          child: Text(_avatarEmoji, style: const TextStyle(fontSize: AppConstants.emojiIcon2xl)),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.edit, size: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spaceLg),
                AuthTextField(
                  controller: _nameController,
                  label: 'Name',
                  icon: Icons.badge_outlined,
                  validator: (v) => Validators.required(v, fieldName: 'Name'),
                ),
                const SizedBox(height: 12),
                AuthTextField(
                  controller: _ageController,
                  label: 'Age (optional)',
                  icon: Icons.cake_outlined,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final age = int.tryParse(v.trim());
                    if (age == null || age <= 0 || age > 120) return 'Enter a valid age';
                    return null;
                  },
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
                const SizedBox(height: 12),
                AuthTextField(
                  controller: _emailController,
                  label: 'Email',
                  icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  validator: Validators.email,
                ),
                const SizedBox(height: AppConstants.spaceLg),
                AppButton(
                  label: 'Save Changes',
                  isLoading: _isSaving,
                  onPressed: _handleSave,
                ),
                const SizedBox(height: AppConstants.spaceLg),
                AppCard(
                  onTap: () => ChangePasswordDialog.show(context),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline),
                      const SizedBox(width: 12),
                      const Expanded(child: Text('Change Password')),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
