import 'package:famotive/app/routes.dart';
import 'package:famotive/core/models/user.dart';
import 'package:famotive/core/services/notification_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationService.routeFor', () {
    test('task notifications open the task detail screen', () {
      for (final type in [
        'task_assigned',
        'task_due',
        'task_overdue',
        'task_approved',
        'task_accepted',
        'task_completed',
      ]) {
        final route = NotificationService.routeFor({'type': type, 'taskId': 't1'});
        expect(route?.name, AppRoutes.taskDetail, reason: type);
        expect(route?.arguments, 't1', reason: type);
        expect(route?.replaceStack, isFalse, reason: type);
      }
    });

    test('new pool tasks and redemptions open the second tab', () {
      for (final type in ['task_available', 'reward_redeemed', 'daily_digest']) {
        final route = NotificationService.routeFor({'type': type, 'taskId': 't1'});
        expect(route?.name, AppRoutes.family, reason: type);
        expect(route?.replaceStack, isTrue, reason: type);
      }
    });

    test('unknown or incomplete payloads are ignored', () {
      expect(NotificationService.routeFor({}), isNull);
      expect(NotificationService.routeFor({'type': 'something_new'}), isNull);
      expect(NotificationService.routeFor({'type': 'task_assigned'}), isNull);
    });
  });

  group('AppUser.pushNotificationsEnabled', () {
    test('defaults to true for existing profiles without the field', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('users').doc('u1').set({'name': 'Sam', 'role': 'child'});
      final user = AppUser.fromFirestore(await firestore.collection('users').doc('u1').get());
      expect(user.pushNotificationsEnabled, isTrue);
    });

    test('round-trips through Firestore and copyWith', () async {
      final firestore = FakeFirebaseFirestore();
      const user = AppUser(id: 'u1', name: 'Sam', email: 's@x.com', role: UserRole.child);
      await firestore
          .collection('users')
          .doc('u1')
          .set(user.copyWith(pushNotificationsEnabled: false).toFirestore());
      final loaded = AppUser.fromFirestore(await firestore.collection('users').doc('u1').get());
      expect(loaded.pushNotificationsEnabled, isFalse);
      expect(loaded.copyWith(name: 'Sammy').pushNotificationsEnabled, isFalse);
    });
  });
}
