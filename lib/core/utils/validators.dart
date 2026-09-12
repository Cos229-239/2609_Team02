/// Small, dependency-free form validators shared by auth (and future)
/// forms. Each returns a user-facing error string, or `null` when valid.
class Validators {
  Validators._();

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? required(String? value, {String fieldName = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your $fieldName';
    }
    return null;
  }

  /// Accepts either an email address or a phone number, matching the
  /// "Email or Phone" field shown on the login wireframe.
  static String? emailOrPhone(String? value) {
    final error = required(value, fieldName: 'Email or phone');
    if (error != null) return error;

    final trimmed = value!.trim();
    final isPhone = RegExp(r'^[0-9+()\-\s]{7,}$').hasMatch(trimmed);
    final isEmail = _emailPattern.hasMatch(trimmed);
    if (!isPhone && !isEmail) {
      return 'Please enter a valid email address or phone number';
    }
    return null;
  }

  static String? email(String? value) {
    final error = required(value, fieldName: 'Email');
    if (error != null) return error;
    if (!_emailPattern.hasMatch(value!.trim())) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  static String? phone(String? value) {
   if (value == null || value.trim().isEmpty) return null; // optional field
   final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 10) {
      return 'Please enter a valid 10-digit phone number';
    }
    return null;
  }

  static String? password(String? value) {
    final error = required(value, fieldName: 'Password');
    if (error != null) return error;
    if (value!.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }
  static String? Function(String?) confirmPassword(
    String? Function() getPassword,
  ) {
    return (value) {
      final error = required(value, fieldName: 'Confirm password');
      if (error != null) return error;
      if (value != getPassword()) {
        return 'Passwords do not match';
      }
      return null;
    };
  }
}
