import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../constants/app_constants.dart';
import '../models/join_request.dart';
import '../models/reward.dart';
import '../models/task.dart';
import '../models/task_schedule.dart';
import '../models/user.dart';
import 'time_zone_service.dart';

/// Handles sign-in/sign-up/session state against Firebase Auth, with each
/// user's profile (name, role, xp, householdId, ...) stored in Firestore
/// under `users/{uid}` since Firebase Auth itself only knows email/uid.
/// Creates a Firebase Auth account for a child and writes its profile
/// (signed in as that child), returning the new uid. See
/// [AuthService.createChildAccount].
typedef ChildAccountCreator = Future<String> Function({
  required String email,
  required String password,
  required Map<String, dynamic> profile,
});

/// Shows the Google account picker and returns the chosen account's ID
/// token, or null if the user backed out. Swapped out in tests.
typedef GoogleIdTokenProvider = Future<String?> Function();

/// Outcome of [AuthService.signInWithGoogle] / [AuthService.signInWithApple].
///
/// Either the account already has a Famotive profile ([user] is set and the
/// session is live), or it's brand new ([needsSetup]): Firebase is signed in
/// but there's no `users/{uid}` profile yet, so the app shows
/// FinishSignUpScreen to pick a role/household and then calls
/// [AuthService.completeSocialSignUp].
class SocialSignInResult {
  const SocialSignInResult.signedIn(AppUser this.user)
      : suggestedName = null,
        email = null;
  const SocialSignInResult.needsSetup({this.suggestedName, this.email}) : user = null;

  final AppUser? user;

  /// Name from the Google/Apple account, to prefill the setup form.
  final String? suggestedName;
  final String? email;

  bool get needsSetup => user == null;
}

/// Calls the `deleteAccount` Cloud Function (functions/src/account/delete.ts)
/// and returns its result. Swapped out in tests.
typedef AccountDeletionCall = Future<Map<String, dynamic>> Function(Map<String, dynamic> data);

/// What deleting an account would do, from a `dryRun` of `deleteAccount`.
class AccountDeletionPreview {
  AccountDeletionPreview.fromMap(Map<String, dynamic> m)
      : forbidden = m['forbidden'] as String?,
        blockers = _strings(m['blockers']),
        deletedHouseholds = _strings(m['deletedHouseholds']),
        leftHouseholds = _strings(m['leftHouseholds']),
        deletedAccounts = _strings(m['deletedAccounts']);

  /// Set if the caller may not delete this account at all.
  final String? forbidden;

  /// Things to do first (e.g. hand over the admin role).
  final List<String> blockers;

  /// Households deleted for everyone, with all their tasks and rewards.
  final List<String> deletedHouseholds;

  /// Households the account is just removed from.
  final List<String> leftHouseholds;

  /// Other (child) accounts deleted along with this one.
  final List<String> deletedAccounts;

  bool get canDelete => forbidden == null && blockers.isEmpty;

  static List<String> _strings(Object? v) =>
      v is List ? v.whereType<String>().toList() : const [];
}

class AuthService extends ChangeNotifier {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    this._childAccountCreator,
    this._googleIdTokenProvider,
    this._accountDeletionCall,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final ChildAccountCreator? _childAccountCreator;
  final GoogleIdTokenProvider? _googleIdTokenProvider;
  final AccountDeletionCall? _accountDeletionCall;

  /// From the last Apple re-authentication; used to revoke Apple's tokens
  /// when the account is deleted (Apple requires it).
  String? _appleAuthorizationCode;

  /// GoogleSignIn.instance.initialize may only be called once per app run.
  static Future<void>? _googleInit;

  AppUser? _currentUser;

  /// Keeps [currentUser] live (active household, pending join requests,
  /// coins, ...) instead of a login-time snapshot.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  void _watchProfile(String uid) {
    unawaited(_profileSub?.cancel());
    _profileSub = _firestore.collection('users').doc(uid).snapshots().listen(
      (snap) {
        if (!snap.exists || _currentUser?.id != uid) return;
        _currentUser = AppUser.fromFirestore(snap);
        notifyListeners();
      },
      onError: (Object e) => debugPrint('AuthService: profile listener error: $e'),
    );
  }

  void _stopWatchingProfile() {
    unawaited(_profileSub?.cancel());
    _profileSub = null;
  }

  @override
  void dispose() {
    _stopWatchingProfile();
    super.dispose();
  }

  /// Run (best-effort) while still signed in, right before [logout] signs
  /// out — e.g. NotificationService removing this device's push token,
  /// which Firestore rules only allow its signed-in owner to do.
  final List<Future<void> Function()> _beforeLogoutHooks = [];

  void addBeforeLogoutHook(Future<void> Function() hook) => _beforeLogoutHooks.add(hook);

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
      if (_currentUser != null) _watchProfile(user.uid);
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
      profile = profile.copyWith(email: authEmail);
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
    _watchProfile(profile.id);
    notifyListeners();
    return profile;
  }

  /// Creates a Firebase Auth account and a matching Firestore profile.
  ///
  /// A parent without an [inviteCode] gets a brand-new household (with a
  /// generated invite code) and becomes its admin. With an [inviteCode]
  /// (always, for children) the account asks to join that household instead
  /// and waits until the household's admin approves it.
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
    try {
      return await _createProfile(
        uid: cred.user!.uid,
        name: name,
        email: email.trim(),
        role: role,
        phoneNumber: phoneNumber,
        inviteCode: inviteCode,
      );
    } catch (e) {
      // Roll back the auth account so a failed registration doesn't leave
      // behind a stranded account with no profile/household.
      await cred.user?.delete().catchError((_) {});
      await _auth.signOut();
      rethrow;
    }
  }

  /// Writes `users/{uid}` for the signed-in account and either creates its
  /// household (parent, no code) or files a join request (child, or a code).
  Future<AppUser> _createProfile({
    required String uid,
    required String name,
    required String email,
    required UserRole role,
    String? phoneNumber,
    String? inviteCode,
  }) async {
    final code = (inviteCode ?? '').trim();
    final joining = role == UserRole.child || code.isNotEmpty;

    // Look the household up first so a bad code fails before anything
    // is written.
    final joinRef = joining ? await _householdByInviteCode(code) : null;
    final householdId = joining ? null : await _createHousehold(name: name);

    final user = AppUser(
      id: uid,
      name: name,
      email: email,
      role: role,
      phoneNumber: phoneNumber,
      avatarEmoji: role == UserRole.parent ? '👩' : '🧒',
      householdId: householdId,
      pendingHouseholdIds: joinRef == null ? const [] : [joinRef.id],
    );
    await _firestore.collection('users').doc(uid).set({
      ...user.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (joinRef != null) await _fileJoinRequest(joinRef, user);

    _currentUser = user;
    _watchProfile(uid);
    notifyListeners();
    return user;
  }

  // --- Google / Apple sign-in ---------------------------------------------

  /// True if the signed-in account can log in with an email + password
  /// (false for accounts made with Google/Apple only, which have no
  /// password to re-enter for changing email or password).
  bool get hasPasswordLogin =>
      _auth.currentUser?.providerData.any((p) => p.providerId == 'password') ?? false;

  /// "Google" / "Apple" for accounts without a password, else null.
  String? get socialProviderName {
    if (hasPasswordLogin) return null;
    final ids = _auth.currentUser?.providerData.map((p) => p.providerId) ?? const <String>[];
    if (ids.contains('apple.com')) return 'Apple';
    if (ids.contains('google.com')) return 'Google';
    return null;
  }

  /// Signs in with Google. Returns null if the user cancelled the picker.
  /// Works for both new and returning users: see [SocialSignInResult].
  Future<SocialSignInResult?> signInWithGoogle() async {
    final idToken = await (_googleIdTokenProvider ?? _nativeGoogleIdToken)();
    if (idToken == null) return null;
    return _finishSocialSignIn(
      () => _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken)),
    );
  }

  /// Signs in with Apple (iOS: the native Apple sheet). Returns null if the
  /// user cancelled. See [SocialSignInResult].
  Future<SocialSignInResult?> signInWithApple() {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    return _finishSocialSignIn(() => _auth.signInWithProvider(provider));
  }

  Future<String?> _nativeGoogleIdToken() async {
    final google = GoogleSignIn.instance;
    try {
      await (_googleInit ??= google.initialize(
        // iOS needs its OAuth client id; Android needs the project's *web*
        // client id so the ID token is one Firebase accepts.
        clientId: defaultTargetPlatform == TargetPlatform.iOS ? AppConstants.googleIosClientId : null,
        serverClientId: AppConstants.googleServerClientId,
      ));
      final account = await google.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      debugPrint('Google sign-in failed: ${e.code} ${e.description}');
      throw Exception('Google sign-in failed. Please try again.');
    }
  }

  Future<SocialSignInResult?> _finishSocialSignIn(Future<UserCredential> Function() signIn) async {
    final UserCredential cred;
    try {
      cred = await signIn();
    } on FirebaseAuthException catch (e) {
      if (_isCancellation(e)) return null;
      throw Exception(_friendlyAuthError(e));
    }
    final user = cred.user!;

    final profile = await _loadProfile(user.uid);
    if (profile != null) {
      _currentUser = profile;
      _watchProfile(profile.id);
      notifyListeners();
      return SocialSignInResult.signedIn(profile);
    }

    final displayName = user.displayName?.trim() ?? '';
    return SocialSignInResult.needsSetup(
      suggestedName: displayName.isNotEmpty ? displayName : _providerProfileName(cred),
      email: user.email,
    );
  }

  /// The name the provider sent with the sign-in, if any. Only read when the
  /// Firebase user has no display name (e.g. Apple after the first sign-in);
  /// optional, so a credential that can't supply it just means no prefill.
  static String? _providerProfileName(UserCredential cred) {
    try {
      final name = cred.additionalUserInfo?.profile?['name'];
      return name is String && name.trim().isNotEmpty ? name.trim() : null;
    } catch (e) {
      debugPrint('AuthService: no provider profile name: $e');
      return null;
    }
  }

  static bool _isCancellation(FirebaseAuthException e) {
    const codes = {'canceled', 'cancelled', 'web-context-canceled', 'user-cancelled', 'popup-closed-by-user'};
    if (codes.contains(e.code)) return true;
    // iOS reports a dismissed Apple sheet as AuthorizationError 1001.
    final message = e.message ?? '';
    return message.contains('AuthorizationError error 1001') || message.contains('error 1001');
  }

  /// Finishes signing up a brand-new Google/Apple account (after
  /// [signInWithGoogle]/[signInWithApple] returned [SocialSignInResult.needsSetup]).
  /// Same household rules as [register].
  Future<AppUser> completeSocialSignUp({
    required String name,
    UserRole role = UserRole.parent,
    String? phoneNumber,
    String? inviteCode,
  }) async {
    final fbUser = _auth.currentUser;
    if (fbUser == null) throw Exception('Your sign-in expired. Please try again.');
    return _createProfile(
      uid: fbUser.uid,
      name: name.trim(),
      email: fbUser.email ?? '',
      role: role,
      phoneNumber: phoneNumber,
      inviteCode: inviteCode,
    );
  }

  /// Backs out of an unfinished Google/Apple sign-up: removes the auth
  /// account (it has no profile yet) and signs out.
  Future<void> cancelSocialSignUp() async {
    final fbUser = _auth.currentUser;
    if (fbUser != null && _currentUser == null) {
      try {
        final snap = await _firestore.collection('users').doc(fbUser.uid).get();
        if (!snap.exists) await fbUser.delete();
      } catch (e) {
        debugPrint('AuthService: could not remove unfinished sign-up: $e');
      }
    }
    await _signOutEverywhere();
  }

  Future<void> _signOutEverywhere() async {
    await _auth.signOut();
    // Forget the Google account so the picker shows again next time.
    if (_googleInit != null) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (e) {
        debugPrint('Google sign-out failed: $e');
      }
    }
  }

  /// Creates a household with the signed-in user as its admin and only
  /// member, seeded with starter rewards and tasks. Returns its id.
  Future<String> _createHousehold({required String name, String? householdName}) async {
    final householdRef = _firestore.collection('households').doc();
    final inviteCode = await _generateUniqueInviteCode();
    final timezone = await TimeZoneService.localTimeZone();
    final uid = _auth.currentUser!.uid;
    await householdRef.set({
      'name': householdName ?? "$name's Family",
      'inviteCode': inviteCode,
      'ownerId': uid,
      'memberIds': [uid],
      // Drives the 9 AM reminders / repeating tasks (see Household.timezone).
      'timezone': ?timezone,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final batch = _firestore.batch();
    final rewardsRef = householdRef.collection('rewards');
    for (final reward in Reward.defaultCatalog) {
      batch.set(rewardsRef.doc(), reward.toFirestore());
    }
    final now = DateTime.now();
    final tasksRef = householdRef.collection('tasks');
    for (final task in TaskModel.defaultAvailableCatalog(now)) {
      batch.set(tasksRef.doc(), task.toFirestore());
    }
    final schedulesRef = householdRef.collection('taskSchedules');
    for (final schedule in TaskSchedule.defaultCatalog(now)) {
      batch.set(schedulesRef.doc(), schedule.toFirestore());
    }
    await batch.commit();

    return householdRef.id;
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _householdByInviteCode(String? inviteCode) async {
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
    return query.docs.first;
  }

  /// Files `households/{id}/joinRequests/{uid}` for the household's admin to
  /// approve. Never adds [user] to the household by itself.
  Future<void> _fileJoinRequest(DocumentSnapshot<Map<String, dynamic>> household, AppUser user) async {
    final request = JoinRequest(
      userId: user.id,
      householdId: household.id,
      name: user.name,
      email: user.email,
      role: user.role,
      avatarEmoji: user.avatarEmoji,
      householdName: household.data()?['name'] as String?,
      requestedAt: DateTime.now(),
    );
    await household.reference.collection('joinRequests').doc(user.id).set(request.toFirestore());
  }

  // --- Households ---------------------------------------------------------

  AppUser _requireUser() {
    final user = _currentUser;
    if (user == null) throw Exception('Not signed in.');
    return user;
  }

  Future<void> _updateSelf(Map<String, dynamic> fields, AppUser updated) async {
    await _firestore.collection('users').doc(updated.id).update(fields);
    _currentUser = updated;
    notifyListeners();
  }

  /// Makes [householdId] the household the app shows (null: none).
  Future<void> switchHousehold(String? householdId) async {
    final user = _requireUser();
    if (user.householdId == householdId) return;
    await _updateSelf(
      {'householdId': householdId},
      user.copyWith(householdId: householdId, clearHouseholdId: householdId == null),
    );
  }

  /// Asks to join the household with [inviteCode]. Its admin has to approve
  /// before the household shows up. Returns the household's name.
  Future<String> requestToJoinHousehold(String inviteCode) async {
    final user = _requireUser();
    final household = await _householdByInviteCode(inviteCode);
    final data = household.data() ?? const {};
    final memberIds = List<String>.from(data['memberIds'] as List? ?? const []);
    final name = data['name'] as String? ?? 'that household';
    if (memberIds.contains(user.id)) {
      throw Exception("You're already a member of $name.");
    }
    if (user.pendingHouseholdIds.contains(household.id)) {
      throw Exception('You already asked to join $name - waiting for the admin.');
    }
    await _fileJoinRequest(household, user);
    if (!user.pendingHouseholdIds.contains(household.id)) {
      final pending = [...user.pendingHouseholdIds, household.id];
      await _updateSelf({'pendingHouseholdIds': pending}, user.copyWith(pendingHouseholdIds: pending));
    }
    return name;
  }

  /// Withdraws a join request that hasn't been answered yet.
  Future<void> cancelJoinRequest(String householdId) async {
    final user = _requireUser();
    try {
      await _firestore
          .collection('households')
          .doc(householdId)
          .collection('joinRequests')
          .doc(user.id)
          .delete();
    } catch (e) {
      debugPrint('AuthService: could not delete join request: $e');
    }
    await forgetPendingHousehold(householdId);
  }

  /// Drops [householdId] from the pending list once its request was
  /// approved or declined (see DatabaseService.onPendingRequestResolved).
  /// An approved household becomes the active one if none is active yet.
  Future<void> forgetPendingHousehold(String householdId, {bool approved = false}) async {
    final user = _currentUser;
    if (user == null || !user.pendingHouseholdIds.contains(householdId)) return;
    final pending = user.pendingHouseholdIds.where((id) => id != householdId).toList();
    final activate = approved && user.householdId == null;
    await _updateSelf(
      {
        'pendingHouseholdIds': pending,
        if (activate) 'householdId': householdId,
      },
      user.copyWith(pendingHouseholdIds: pending, householdId: activate ? householdId : null),
    );
  }

  /// Creates another household with the signed-in parent as admin and
  /// switches to it.
  Future<String> createHousehold({required String householdName}) async {
    final user = _requireUser();
    if (!user.isParent) throw Exception('Only parents can create a household.');
    final name = householdName.trim();
    if (name.isEmpty) throw Exception('Give your household a name.');
    final id = await _createHousehold(name: user.name, householdName: name);
    await switchHousehold(id);
    return id;
  }

  /// Leaves [householdId]. The admin has to hand the admin role to another
  /// parent first (or remove everyone else). XP and coins are kept.
  Future<void> leaveHousehold(String householdId, {String? switchTo}) async {
    final user = _requireUser();
    final ref = _firestore.collection('households').doc(householdId);
    final snap = await ref.get();
    final data = snap.data() ?? const {};
    final memberIds = List<String>.from(data['memberIds'] as List? ?? const []);
    if (data['ownerId'] == user.id && memberIds.length > 1) {
      throw Exception('You are the admin. Make another parent the admin before leaving.');
    }
    if (data['ownerId'] == user.id) {
      throw Exception("You're the only member - the household can't be left empty.");
    }
    await ref.update({'memberIds': FieldValue.arrayRemove([user.id])});
    if (user.householdId == householdId) await switchHousehold(switchTo);
  }

  /// "parent+ava@example.com" for a parent at parent@example.com adding a
  /// child named "Ava": many kids don't have an email of their own, and plus
  /// addresses land in the parent's inbox (so do password resets).
  static String suggestChildEmail(String parentEmail, String childName) {
    final at = parentEmail.lastIndexOf('@');
    final tag = childName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (at <= 0 || tag.isEmpty) return '';
    final local = parentEmail.substring(0, at).split('+').first;
    final domain = parentEmail.substring(at + 1);
    return '$local+$tag@$domain';
  }

  /// Creates a login for a child (who may not have an email of their own:
  /// see [suggestChildEmail]) and adds it to [householdId] straight away -
  /// no approval needed, since a parent member created it. The parent stays
  /// signed in. Returns the child's uid.
  Future<String> createChildAccount({
    required String householdId,
    required String name,
    required String email,
    required String password,
    int? age,
    String avatarEmoji = '🧒',
  }) async {
    final parent = _requireUser();
    if (!parent.isParent) throw Exception('Only parents can add a child.');

    final profile = AppUser(
      id: '',
      name: name.trim(),
      email: email.trim(),
      role: UserRole.child,
      age: age,
      avatarEmoji: avatarEmoji,
      householdId: householdId,
      createdByParentId: parent.id,
    ).toFirestore();

    final creator = _childAccountCreator ?? _createAccountInSecondaryApp;
    final uid = await creator(email: email.trim(), password: password, profile: profile);

    await _firestore.collection('households').doc(householdId).update({
      'memberIds': FieldValue.arrayUnion([uid]),
    });
    return uid;
  }

  /// Signs the new account up on a throwaway second FirebaseApp so the
  /// parent's own session (on the default app) is untouched, writes the
  /// child's profile as the child (rules only let users create their own
  /// profile), then signs out and disposes of that app.
  Future<String> _createAccountInSecondaryApp({
    required String email,
    required String password,
    required Map<String, dynamic> profile,
  }) async {
    final app = await Firebase.initializeApp(
      name: 'child-signup-${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );
    try {
      final auth = FirebaseAuth.instanceFor(app: app);
      final UserCredential cred;
      try {
        cred = await auth.createUserWithEmailAndPassword(email: email, password: password);
      } on FirebaseAuthException catch (e) {
        throw Exception(_friendlyAuthError(e));
      }
      final uid = cred.user!.uid;
      try {
        await FirebaseFirestore.instanceFor(app: app).collection('users').doc(uid).set({
          ...profile,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        await cred.user?.delete().catchError((_) {});
        rethrow;
      }
      await auth.signOut();
      return uid;
    } finally {
      await app.delete();
    }
  }

  // --- Account deletion ---------------------------------------------------

  /// Asks the server what deleting the signed-in account (or, for an admin
  /// parent, [childId]'s account) would do. Changes nothing.
  Future<AccountDeletionPreview> previewAccountDeletion({String? childId}) async {
    _requireUser();
    final result = await _callDeleteAccount({'dryRun': true, 'childId': ?childId});
    return AccountDeletionPreview.fromMap(result);
  }

  /// Re-authenticates the signed-in user right before a destructive action
  /// (the server only deletes accounts for a sign-in less than 5 minutes
  /// old). Password accounts pass [password]; Google/Apple accounts get
  /// their provider's sign-in sheet. Returns false if the user cancelled.
  Future<bool> confirmIdentity({String? password}) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in.');
    final providers = user.providerData.map((p) => p.providerId).toSet();
    try {
      if (providers.contains('password')) {
        if (password == null) return false;
        await _reauthenticate(password);
      } else if (providers.contains('apple.com')) {
        final cred = await user.reauthenticateWithProvider(AppleAuthProvider());
        _appleAuthorizationCode = cred.additionalUserInfo?.authorizationCode;
      } else if (providers.contains('google.com')) {
        final idToken = await (_googleIdTokenProvider ?? _nativeGoogleIdToken)();
        if (idToken == null) return false;
        await user.reauthenticateWithCredential(GoogleAuthProvider.credential(idToken: idToken));
      } else {
        throw Exception('Please log out and back in, then try again.');
      }
    } on FirebaseAuthException catch (e) {
      if (_isCancellation(e)) return false;
      throw Exception(_friendlyAuthError(e));
    }
    // Make sure the server sees the fresh sign-in time.
    await _auth.currentUser?.getIdToken(true);
    return true;
  }

  /// Permanently deletes the signed-in account (call [confirmIdentity]
  /// first). If they're the only parent in a household they run, that
  /// household and the child logins they made for it go too; see
  /// [previewAccountDeletion]. Signs out afterwards.
  Future<void> deleteAccount() async {
    _requireUser();

    // Apple requires revoking its tokens when an account is deleted.
    final appleCode = _appleAuthorizationCode;
    _appleAuthorizationCode = null;
    if (appleCode != null) {
      try {
        await _auth.revokeTokenWithAuthorizationCode(appleCode);
      } catch (e) {
        debugPrint('AuthService: revoking Apple token failed: $e');
      }
    }

    await _callDeleteAccount(const {});

    // The account is gone server-side; clean up this device and sign out.
    for (final hook in List.of(_beforeLogoutHooks)) {
      try {
        await hook();
      } catch (e) {
        debugPrint('Before-logout hook failed: $e');
      }
    }
    _stopWatchingProfile();
    _currentUser = null;
    try {
      await _signOutEverywhere();
    } catch (e) {
      debugPrint('AuthService: sign-out after deletion failed: $e');
    }
    notifyListeners();
  }

  /// An admin parent permanently deletes one of their children's accounts
  /// (call [confirmIdentity] first).
  Future<void> deleteChildAccount(String childId) async {
    final me = _requireUser();
    if (!me.isParent) throw Exception('Only parents can delete a child account.');
    await _callDeleteAccount({'childId': childId});
  }

  Future<Map<String, dynamic>> _callDeleteAccount(Map<String, dynamic> data) {
    return (_accountDeletionCall ?? _cloudDeleteAccount)(data);
  }

  static Future<Map<String, dynamic>> _cloudDeleteAccount(Map<String, dynamic> data) async {
    try {
      final result = await FirebaseFunctions.instance.httpsCallable('deleteAccount').call(data);
      final raw = result.data;
      return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      debugPrint('deleteAccount failed: ${e.code} ${e.message}');
      switch (e.code) {
        // The deleteAccount Cloud Function isn't deployed (or wrong region).
        case 'not-found':
        case 'unimplemented':
          throw Exception(
            "Account deletion isn't available right now. Please try again later "
            'or email support@famotive.org.',
          );
        // Usually the function's Cloud Run service isn't publicly invokable
        // (see functions/README.md), or the sign-in token expired.
        case 'unauthenticated':
          throw Exception("Couldn't verify your sign-in with the server. Log out and back in, then try again.");
        case 'unavailable':
        case 'deadline-exceeded':
          throw Exception('Network error: check your connection and try again.');
        default:
          throw Exception(e.message ?? 'Something went wrong. Please try again.');
      }
    }
  }

  Future<void> logout() async {
    for (final hook in List.of(_beforeLogoutHooks)) {
      try {
        await hook();
      } catch (e) {
        debugPrint('Before-logout hook failed: $e');
      }
    }
    _stopWatchingProfile();
    await _signOutEverywhere();
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

    // Built directly, not via `copyWith`, so an explicit null clears
    // phoneNumber/age instead of leaving them unchanged.
    final updated = AppUser(
      id: user.id,
      name: name,
      email: user.email,
      role: user.role,
      avatarEmoji: avatarEmoji,
      phoneNumber: phoneNumber,
      age: age,
      xp: user.xp,
      coins: user.coins,
      householdId: user.householdId,
      pinnedRewardId: user.pinnedRewardId,
      pushNotificationsEnabled: user.pushNotificationsEnabled,
      pendingHouseholdIds: user.pendingHouseholdIds,
      createdByParentId: user.createdByParentId,
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

  /// Turns push notifications on/off for the signed-in user (all devices).
  Future<void> setPushNotificationsEnabled(bool enabled) async {
    final user = _currentUser;
    if (user == null) throw Exception('Not signed in.');

    await _firestore.collection('users').doc(user.id).update({
      'pushNotificationsEnabled': enabled,
    });
    _currentUser = user.copyWith(pushNotificationsEnabled: enabled);
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
      // Best-effort only: see comment above.
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
      // Don't reveal whether an account exists for this email: treat it
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
        return 'Password is too weak: use at least 6 characters.';
      case 'expired-action-code':
        return 'This reset link has expired. Request a new one.';
      case 'invalid-action-code':
        return 'This reset link is invalid or has already been used.';
      case 'network-request-failed':
        return 'Network error: check your connection and try again.';
      case 'requires-recent-login':
        return 'Please log out and back in, then try again.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email. Log in with your email and password instead.';
      case 'user-mismatch':
        return "That's a different account. Use the one you're signed in with.";
      case 'operation-not-allowed':
        return "This sign-in method isn't turned on yet.";
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
