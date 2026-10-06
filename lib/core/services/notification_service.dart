import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../models/user.dart';
import 'auth_service.dart';

/// Push notifications via Firebase Cloud Messaging.
///
/// The notifications themselves are sent by Cloud Functions
/// (functions/src/index.ts) in response to Firestore changes:
///   - children: new task available / assigned, approved, and a 9 AM
///     (household time) digest of what's due today / overdue
///   - parents:  task accepted (claimed), task completed, reward redeemed
///
/// This service only has to:
///   1. ask for notification permission and store this device's FCM token
///      at `users/{uid}/fcmTokens/{token}` while someone is signed in,
///   2. remove that token again on logout (so the next person to sign in on
///      this device doesn't get the previous user's notifications),
///   3. show a banner for notifications arriving while the app is open
///      (the OS only displays them when the app is in the background), and
///   4. open the relevant screen when a notification is tapped.
class NotificationService {
  NotificationService({
    required AuthService authService,
    required this._navigatorKey,
    required this._messengerKey,
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
  })  : _auth = authService,
        _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final AuthService _auth;
  final GlobalKey<NavigatorState> _navigatorKey;
  final GlobalKey<ScaffoldMessengerState> _messengerKey;
  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;

  /// The user this device is being (or has been) registered for. Changes as
  /// soon as auth changes, so an in-flight registration can tell it is stale.
  String? _registeredUid;

  /// The FCM token saved in Firestore, and the user it was saved under.
  String? _token;
  String? _tokenUid;

  final List<StreamSubscription<dynamic>> _subs = [];

  /// Call once, after `runApp` (so the Navigator exists for cold-start taps).
  Future<void> init() async {
    _auth.addListener(_onAuthChanged);
    _auth.addBeforeLogoutHook(unregisterDevice);

    _subs
      ..add(FirebaseMessaging.onMessage.listen(_showForegroundBanner))
      ..add(FirebaseMessaging.onMessageOpenedApp.listen(_openFromNotification))
      ..add(_messaging.onTokenRefresh.listen((token) => unawaited(_onTokenRefresh(token))));

    // App was launched by tapping a notification while it was terminated.
    try {
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _openFromNotification(initial);
    } catch (e) {
      debugPrint('NotificationService: getInitialMessage failed: $e');
    }

    _onAuthChanged();
  }

  void dispose() {
    _auth.removeListener(_onAuthChanged);
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
  }

  // --- Registration -----------------------------------------------------------

  void _onAuthChanged() {
    final user = _auth.currentUser;
    if (user == null) {
      _registeredUid = null;
      return;
    }
    if (user.id == _registeredUid) return;
    _registeredUid = user.id;
    unawaited(_register(user));
  }

  /// (Re-)registers this device for the signed-in user — e.g. after they
  /// switch push notifications back on in Settings. Returns false when the
  /// OS permission is denied (the user must enable it in system settings).
  Future<bool> registerCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    _registeredUid = user.id;
    return _register(user, force: true);
  }

  Future<bool> _register(AppUser user, {bool force = false}) async {
    // Don't prompt for permission if they've opted out in Settings.
    if (!user.pushNotificationsEnabled && !force) {
      debugPrint('NotificationService: push disabled in Settings for ${user.id}');
      return false;
    }

    try {
      final settings = await _messaging.requestPermission(alert: true, badge: true, sound: true);
      final status = settings.authorizationStatus;
      debugPrint('NotificationService: permission = ${status.name}');
      if (status == AuthorizationStatus.denied || status == AuthorizationStatus.notDetermined) {
        return false;
      }

      // On iOS the FCM token can only be fetched once APNs has handed the
      // app its device token, which can lag a moment behind app start.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        String? apns;
        for (var attempt = 0; attempt < 10 && apns == null; attempt++) {
          apns = await _messaging.getAPNSToken();
          if (apns == null) await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (apns == null) {
          debugPrint('NotificationService: no APNs token (simulator without push support?)');
          return false;
        }
      }

      final token = await _messaging.getToken();
      if (token == null) {
        debugPrint('NotificationService: getToken returned null');
        return false;
      }

      // The permission prompt and APNs wait above can take a while. If
      // someone logged out (or another user logged in) meanwhile, this
      // registration is stale: saving now would attach this device to the
      // wrong account.
      if (!_isCurrent(user.id)) {
        debugPrint('NotificationService: auth changed during registration for ${user.id}; skipped');
        return false;
      }

      // Recorded before the write so a logout racing it still deletes it.
      _token = token;
      _tokenUid = user.id;
      await _saveToken(user.id, token);
      debugPrint('NotificationService: registered device for ${user.id}');
      return true;
    } catch (e) {
      debugPrint('NotificationService: registration failed: $e');
      return false;
    }
  }

  /// True while [uid] is both signed in and the user being registered.
  bool _isCurrent(String uid) => _registeredUid == uid && _auth.currentUser?.id == uid;

  DocumentReference<Map<String, dynamic>> _tokenDoc(String uid, String token) =>
      _firestore.collection('users').doc(uid).collection('fcmTokens').doc(token);

  Future<void> _saveToken(String uid, String token) => _tokenDoc(uid, token).set({
        'platform': defaultTargetPlatform.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// FCM rotated this device's token: move the registration to the new one,
  /// for the user it was saved under (never whoever happens to be signed in
  /// — and nobody, if this device was never registered or has logged out).
  Future<void> _onTokenRefresh(String token) async {
    final uid = _tokenUid;
    final old = _token;
    if (uid == null || !_isCurrent(uid) || token == old) return;
    _token = token;
    try {
      await _saveToken(uid, token);
      if (old != null) await _tokenDoc(uid, old).delete();
    } catch (e) {
      debugPrint('NotificationService: saving refreshed token failed: $e');
    }
  }

  /// Removes this device's token so it stops receiving the signed-in user's
  /// notifications. Registered as an AuthService before-logout hook.
  ///
  /// Never throws: logout must go ahead even when offline, and the FCM token
  /// is invalidated regardless, so a Firestore record we couldn't delete
  /// points at a dead token that the server prunes on its next send.
  Future<void> unregisterDevice() async {
    final uid = _tokenUid ?? _auth.currentUser?.id;
    final known = _token;
    _token = null;
    _tokenUid = null;
    _registeredUid = null;

    try {
      // Not registered this session (e.g. push was off at startup): there may
      // still be a record from an earlier one under this device's token.
      final token = known ?? await _messaging.getToken();
      if (uid != null && token != null) await _tokenDoc(uid, token).delete();
    } catch (e) {
      debugPrint('NotificationService: removing token from Firestore failed: $e');
    } finally {
      try {
        await _messaging.deleteToken();
      } catch (e) {
        debugPrint('NotificationService: deleteToken failed: $e');
      }
    }
  }

  // --- Display & navigation ---------------------------------------------------

  void _showForegroundBanner(RemoteMessage message) {
    final notification = message.notification;
    final messenger = _messengerKey.currentState;
    if (notification == null || messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (notification.title != null)
                Text(notification.title!, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (notification.body != null) Text(notification.body!),
            ],
          ),
          action: routeFor(message.data) == null
              ? null
              : SnackBarAction(label: 'View', onPressed: () => _openFromNotification(message)),
        ),
      );
  }

  Future<void> _openFromNotification(RemoteMessage message) async {
    final route = routeFor(message.data);
    if (route == null) return;

    // Notifications come from every household the user is in: show the one
    // this is about first.
    final householdId = message.data['householdId'] as String?;
    if (householdId != null &&
        householdId.isNotEmpty &&
        _auth.isLoggedIn &&
        _auth.currentUser?.householdId != householdId) {
      try {
        await _auth.switchHousehold(householdId);
      } catch (e) {
        debugPrint('NotificationService: could not switch household: $e');
      }
    }

    void navigate() {
      final navigator = _navigatorKey.currentState;
      if (navigator == null || !_auth.isLoggedIn) return;
      if (route.replaceStack) {
        navigator.pushNamedAndRemoveUntil(route.name, (_) => false, arguments: route.arguments);
      } else {
        navigator.pushNamed(route.name, arguments: route.arguments);
      }
    }

    // A cold-start tap can arrive before the Navigator exists.
    if (_navigatorKey.currentState != null) {
      navigate();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => navigate());
    }
  }

  /// Where tapping a notification with this `data` payload should go.
  @visibleForTesting
  static NotificationRoute? routeFor(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final taskId = data['taskId'] as String?;

    switch (type) {
      // A new pool task: the child's Tasks tab is where it can be claimed.
      // (AppRoutes.family is the 2nd tab: "Family" for parents, "Tasks" for children.)
      case 'task_available':
        return const NotificationRoute(AppRoutes.family, replaceStack: true);
      // Morning summary of several tasks: the child's Tasks tab lists them all.
      case 'daily_digest':
        return const NotificationRoute(AppRoutes.family, replaceStack: true);
      // Parents review redemptions on the Family tab.
      case 'reward_redeemed':
        return const NotificationRoute(AppRoutes.family, replaceStack: true);
      // Someone asked to join: the admin approves on the Family tab.
      case 'join_requested':
        return const NotificationRoute(AppRoutes.family, replaceStack: true);
      // Let into a household.
      case 'household_joined':
        return const NotificationRoute(AppRoutes.home, replaceStack: true);
      case 'task_assigned':
      case 'task_due':
      case 'task_overdue':
      case 'task_approved':
      case 'task_accepted':
      case 'task_completed':
        if (taskId == null || taskId.isEmpty) return null;
        return NotificationRoute(AppRoutes.taskDetail, arguments: taskId);
      default:
        return null;
    }
  }
}

@immutable
class NotificationRoute {
  const NotificationRoute(this.name, {this.arguments, this.replaceStack = false});

  final String name;
  final Object? arguments;

  /// Reset to this route (used for tab destinations) instead of pushing.
  final bool replaceStack;
}
