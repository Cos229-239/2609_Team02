import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../models/reward.dart';
import '../models/task.dart';
import '../models/user.dart';

/// Handles sign-in/sign-up/session state against Firebase Auth, with each
/// user's profile (name, role, xp, householdId, ...) stored in Firestore
/// under `users/{uid}` since Firebase Auth itself only knows email/uid.
class AuthService extends ChangeNotifier {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  /// Returns the current user's Firebase User, or null if not logged in.
  User? get firebaseUser => _auth.currentUser;

  /// Restores a previous session on app startup, if Firebase Auth still
  /// has a signed-in user and their profile document still exists. Call
  /// this once before the app's widget tree is built.
  Future<void> tryRestoreSession() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      _currentUser = await _loadProfile(user.uid);
    } catch (_) {
      _currentUser = null;
    }
  }

  Future<AppUser?> _loadProfile(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    var profile = AppUser.fromFirestore(doc);

    // Ensure the Firestore profile's email matches the Firebase Auth email.
    final authEmail = _auth.currentUser?.email;
    if (authEmail != null && authEmail.isNotEmpty && authEmail != profile.email) {
      await _firestore.collection('users').doc(uid).update({'email': authEmail});
      profile = AppUser(
        id: profile.id,
        name: profile.name,
        email: authEmail,
        role: profile.role,
        avatarEmoji: profile.avatarEmoji,
        phoneNumber: profile.phoneNumber,
        age: profile.age,
        xp: profile.xp,
        householdId: profile.householdId,
      );
    }

    return profile;
  }

  /// Signs in with email/password and loads the matching Firestore profile.
  Future<AppUser> login({required String email, required String password}) async {
    UserCredential cred;
    try {
      cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendlyAuthError(e));
    }

    final profile = await _loadProfile(cred.user!.uid);
    if (profile == null) {
      await _auth.signOut();
      throw Exception('No profile found for this account.');
    }

    _currentUser = profile;
    notifyListeners();
    return profile;
  }

  /// Creates a Firebase Auth account and a matching Firestore profile.
  ///
  /// Parents get a brand-new household (with a generated invite code).
  /// Children must supply that [inviteCode] to join an existing household.
  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
    UserRole role = UserRole.parent,
    String? phoneNumber,
    String? inviteCode,
  }) async {
    UserCredential cred;
    try {
      cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendlyAuthError(e));
    }
    final uid = cred.user!.uid;

    try {
      final householdId = role == UserRole.parent
          ? await _createHousehold(name: name)
          : await _joinHousehold(inviteCode: inviteCode, uid: uid);

      final user = AppUser(
        id: uid,
        name: name,
        email: email.trim(),
        role: role,
        phoneNumber: phoneNumber,
        avatarEmoji: role == UserRole.parent ? '👩' : '🧒',
        householdId: householdId,
      );
      await _firestore.collection('users').doc(uid).set({
        ...user.toFirestore(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      _currentUser = user;
      notifyListeners();
      return user;
    } catch (e) {
      // Roll back the auth account so a failed registration doesn't leave
      // behind a stranded account with no profile/household.
      await cred.user?.delete().catchError((_) {});
      await _auth.signOut();
      rethrow;
    }
  }

  Future<String> _createHousehold({required String name}) async {
    final householdRef = _firestore.collection('households').doc();
    final inviteCode = await _generateUniqueInviteCode();
    await householdRef.set({
      'name': "$name's Family",
      'inviteCode': inviteCode,
      'memberIds': [_auth.currentUser!.uid],
      'createdAt': FieldValue.serverTimestamp(),
    });

    final batch = _firestore.batch();
    final rewardsRef = householdRef.collection('rewards');
    for (final reward in Reward.defaultCatalog) {
      batch.set(rewardsRef.doc(), reward.toFirestore());
    }
    final tasksRef = householdRef.collection('tasks');
    for (final task in TaskModel.defaultAvailableCatalog(DateTime.now())) {
      batch.set(tasksRef.doc(), task.toFirestore());
    }
    await batch.commit();

    return householdRef.id;
  }

  Future<String> _joinHousehold({required String? inviteCode, required String uid}) async {
    final code = (inviteCode ?? '').trim().toUpperCase();
    if (code.isEmpty) {
      throw Exception('Enter your family invite code.');
    }

    final query = await _firestore
        .collection('households')
        .where('inviteCode', isEqualTo: code)
        .limit(1)
        .get();
    if (query.docs.isEmpty) {
      throw Exception('Invalid invite code. Ask a parent for theirs.');
    }

    final householdRef = query.docs.first.reference;
    await householdRef.update({
      'memberIds': FieldValue.arrayUnion([uid]),
    });
    return householdRef.id;
  }

  Future<void> logout() async {
    await _auth.signOut();
    _currentUser = null;
    notifyListeners();
  }

  Future<void> updateProfile({
    required String name,
    required String avatarEmoji,
    int? age,
    String? phoneNumber,
  }) async {
    final user = _currentUser;
    if (user == null) throw Exception('Not signed in.');

    final updated = AppUser(
      id: user.id,
      name: name,
      email: user.email,
      role: user.role,
      avatarEmoji: avatarEmoji,
      phoneNumber: phoneNumber,
      age: age,
      xp: user.xp,
      householdId: user.householdId,
    );

    await _firestore.collection('users').doc(user.id).update({
      'name': updated.name,
      'avatarEmoji': updated.avatarEmoji,
      'age': updated.age,
      'phoneNumber': updated.phoneNumber,
    });

    _currentUser = updated;
    notifyListeners();
  }

  Future<void> _reauthenticate(String currentPassword) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception('Not signed in.');
    }
    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );
    try {
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendlyAuthError(e));
    }
  }

  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _reauthenticate(currentPassword);
    try {
      await _auth.currentUser!.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendlyAuthError(e));
    }
  }

  Future<void> updateEmail({
    required String newEmail,
    required String currentPassword,
  }) async {
    await _reauthenticate(currentPassword);
    try {
      await _auth.currentUser!.verifyBeforeUpdateEmail(
        newEmail.trim(),
        ActionCodeSettings(
          url: AppConstants.emailChangeContinueUrl,
          handleCodeInApp: true,
          linkDomain: AppConstants.authLinkDomain,
          androidPackageName: AppConstants.androidPackageName,
          androidInstallApp: true,
          androidMinimumVersion: '1',
          iOSBundleId: AppConstants.iosBundleId,
        ),
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendlyAuthError(e));
    }
  }

  Future<String> verifyEmailChangeCode(String oobCode) async {
    try {
      final info = await _auth.checkActionCode(oobCode);
      final newEmail = info.data['email'] as String?;
      if (newEmail == null || newEmail.isEmpty) {
        throw Exception('This link is invalid or has expired.');
      }
      return newEmail;
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendlyAuthError(e));
    }
  }

  Future<void> confirmEmailChange({
    required String oobCode,
    required String newEmail,
    String? uid,
  }) async {
    try {
      await _auth.applyActionCode(oobCode);
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendlyAuthError(e));
    }

    if (uid == null || uid.isEmpty) return;
    try {
      await _firestore.collection('users').doc(uid).update({'email': newEmail});
    } catch (_) {
      // Best-effort only — see comment above.
    }
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(
        email: email.trim(),
        actionCodeSettings: ActionCodeSettings(
          url: AppConstants.passwordResetContinueUrl,
          handleCodeInApp: true,
          linkDomain: AppConstants.authLinkDomain,
          androidPackageName: AppConstants.androidPackageName,
          androidInstallApp: true,
          androidMinimumVersion: '1',
          iOSBundleId: AppConstants.iosBundleId,
        ),
      );
    } on FirebaseAuthException catch (e) {
      // Don't reveal whether an account exists for this email — treat it
      // the same as a successful send so the "check your email" screen
      // can't be used to enumerate registered accounts.
      if (e.code == 'user-not-found') return;
      throw Exception(_friendlyAuthError(e));
    }
  }

  Future<String> verifyPasswordResetCode(String oobCode) async {
    try {
      return await _auth.verifyPasswordResetCode(oobCode);
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendlyAuthError(e));
    }
  }

  Future<void> confirmPasswordReset({
    required String oobCode,
    required String newPassword,
  }) async {
    try {
      await _auth.confirmPasswordReset(code: oobCode, newPassword: newPassword);
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendlyAuthError(e));
    }
  }

  String _friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists with that email.';
      case 'weak-password':
        return 'Password is too weak — use at least 6 characters.';
      case 'expired-action-code':
        return 'This reset link has expired. Request a new one.';
      case 'invalid-action-code':
        return 'This reset link is invalid or has already been used.';
      case 'network-request-failed':
        return 'Network error — check your connection and try again.';
      case 'requires-recent-login':
        return 'Please log out and back in, then try again.';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }

  Future<String> _generateUniqueInviteCode() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = _randomInviteCode();
      final existing = await _firestore
          .collection('households')
          .where('inviteCode', isEqualTo: code)
          .limit(1)
          .get();
      if (existing.docs.isEmpty) return code;
    }
    return _randomInviteCode();
  }

  String _randomInviteCode() {
    // Ambiguous-looking characters (0/O, 1/I, etc.) are left out so codes
    // are easy to read aloud/retype.
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }
}
