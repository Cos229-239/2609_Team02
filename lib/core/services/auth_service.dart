import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/reward.dart';
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
    return AppUser.fromFirestore(doc);
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
      case 'network-request-failed':
        return 'Network error — check your connection and try again.';
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
