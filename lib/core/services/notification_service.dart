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
///   - children: new task available / assigned, due today, past due, approved
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
    required GlobalKey<NavigatorState> navigatorKey,
    required GlobalKey<ScaffoldMessengerState> messengerKey,
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
  })  : _auth = authService,
        _navigatorKey = navigatorKey,
        _messengerKey = messengerKey,
        _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final AuthService _auth;
  final GlobalKey<NavigatorState> _navigatorKey;
  final GlobalKey<ScaffoldMessengerState> _messengerKey;
  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;

  /// The user whose token is currently registered from this device.
  String? _registeredUid;
  String? _token;

  final List<StreamSubscription<dynamic>> _subs = [];

  /// Call once, after `runApp` (so the Navigator exists for cold-start taps).
  Future<void> init() async {
    _auth.addListener(_onAuthChanged);
    _auth.addBeforeLogoutHook(unregisterDevice);

    _subs
      ..add(FirebaseMessaging.onMessage.listen(_showForegroundBanner))
      ..add(FirebaseMessaging.onMessageOpenedApp.listen(_openFromNotification))
      ..add(_messaging.onTokenRefresh.listen((token) {
        _token = token;
        unawaited(_saveToken(token));
      }));

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
      _token = token;
      await _saveToken(token);
      debugPrint('NotificationService: registered device for ${user.id}');
      return true;
    } catch (e) {
      debugPrint('NotificationService: registration failed: $e');
      return false;
    }
  }

  Future<void> _saveToken(String token) async {
    final uid = _auth.currentUser?.id;
    if (uid == null) return;
    await _firestore.collection('users').doc(uid).collection('fcmTokens').doc(token).set({
      'platform': defaultTargetPlatform.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes this device's token so it stops receiving the signed-in user's
  /// notifications. Registered as an AuthService before-logout hook.
  Future<void> unregisterDevice() async {
    final uid = _auth.currentUser?.id;
    final token = _token ?? await _messaging.getToken().catchError((_) => null);
    if (uid != null && token != null) {
      await _firestore.collection('users').doc(uid).collection('fcmTokens').doc(token).delete();
    }
    _token = null;
    _registeredUid = null;
    // Invalidate the token itself too, in case the Firestore delete failed.
    await _messaging.deleteToken().catchError((_) {});
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

  void _openFromNotification(RemoteMessage message) {
    final route = routeFor(message.data);
    if (route == null) return;

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
      // Parents review redemptions on the Family tab.
      case 'reward_redeemed':
        return const NotificationRoute(AppRoutes.family, replaceStack: true);
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
