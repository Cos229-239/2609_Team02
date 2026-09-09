import 'package:flutter/foundation.dart';

import '../models/user.dart';

/// Handles sign-in/sign-up/session state.
///
/// This is a mocked, in-memory implementation so the rest of the app
/// (navigation, feature screens) can be built and demoed end-to-end before
/// a real backend (Firebase Auth, the planned backend) is wired up.
class AuthService extends ChangeNotifier {
  AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  /// Simulates a network round-trip and signs in as a demo parent account.
  /// Any non-empty email/password is accepted — this is a placeholder for
  /// real authentication.
  Future<AppUser> login({required String email, required String password}) async {
    await Future.delayed(const Duration(milliseconds: 600));

    _currentUser = const AppUser(
      id: 'user-parent-1',
      name: 'Jamie',
      email: 'jamie@famotive.app',
      role: UserRole.parent,
      avatarEmoji: '👩',
      householdId: 'household-1',
    );
    notifyListeners();
    return _currentUser!;
  }

  /// Simulates account creation. In the real implementation this would
  /// call Firebase Auth (or another backend) and persist the new user.
  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
    UserRole role = UserRole.parent,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));

    _currentUser = AppUser(
      id: 'user-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      email: email,
      role: role,
      avatarEmoji: role == UserRole.parent ? '👩' : '🧒',
      householdId: 'household-1',
    );
    notifyListeners();
    return _currentUser!;
  }

  Future<void> logout() async {
    _currentUser = null;
    notifyListeners();
  }
}
