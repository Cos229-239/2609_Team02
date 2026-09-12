/// Small, dependency-free form validators shared by auth (and future)
/// forms. Each returns a user-facing error string, or `null` when valid.
class Validators {
  Validators._();

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? required(String? value, {String fieldName = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  static String? email(String? value) {
    final error = required(value, fieldName: 'Email');
    if (error != null) return error;
    if (!_emailPattern.hasMatch(value!.trim())) {
      return 'Enter a valid email address';
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
