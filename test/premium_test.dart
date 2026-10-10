import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:famotive/core/models/household.dart';
import 'package:famotive/core/models/premium_status.dart';
import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/models/user.dart';
import 'package:famotive/core/services/database_service.dart';
import 'package:famotive/core/services/premium_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accountToken matches the server (functions/src/premium/plan.test.ts)', () {
    expect(PremiumService.accountToken('abc'), 'a75d7b44-b1e4-5cba-ad60-5ae51139f501');
    expect(PremiumService.accountToken('abc'), isNot(PremiumService.accountToken('abd')));
  });

  test('PremiumStatus parses the server summary', () {
    final future = DateTime.now().add(const Duration(days: 3));
    final status = PremiumStatus.fromMap({
      'state': 'trial',
      'expiresAt': Timestamp.fromDate(future),
      'isTrial': true,
      'willRenew': true,
      'trialUsed': true,
      'productId': 'famotive_premium_monthly',
      'platform': 'ios',
    });
    expect(status.state, PremiumState.trial);
    expect(status.isActive, isTrue);
    expect(status.isTrial, isTrue);
    expect(status.trialUsed, isTrue);

    final lapsed = PremiumStatus.fromMap({'state': 'billing_retry', 'expiresAt': null, 'trialUsed': true});
    expect(lapsed.isActive, isFalse);
    expect(lapsed.hasPaymentProblem, isTrue);

    expect(PremiumStatus.fromMap(null).state, PremiumState.none);
    expect(PremiumStatus.fromMap({'state': 'something-new'}).state, PremiumState.none);
  });

  test('premium is read from the user doc but never written back', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('users').doc('p1').set({
      'name': 'Pat',
      'email': 'p@example.com',
      'role': 'parent',
      'premium': {'state': 'active', 'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 30)))},
    });
    final user = AppUser.fromFirestore(await firestore.collection('users').doc('p1').get());
    expect(user.premium.isActive, isTrue);
    expect(user.copyWith(name: 'P').premium.isActive, isTrue);
    expect(user.toFirestore().containsKey('premium'), isFalse);
  });

  group('household premium', () {
    late FakeFirebaseFirestore firestore;
    late DatabaseService db;

    Future<void> seed(DateTime? premiumUntil) async {
      await firestore.collection('households').doc('h1').set({
        'name': 'Home',
        'ownerId': 'p1',
        'memberIds': ['p1'],
        'timezone': 'America/Denver',
        if (premiumUntil != null) 'premiumUntil': Timestamp.fromDate(premiumUntil),
      });
      db.bindHousehold('h1');
      await Future<void>.delayed(Duration.zero);
    }

    setUp(() {
      firestore = FakeFirebaseFirestore();
      db = DatabaseService(firestore: firestore, deviceTimeZone: () async => null);
    });

    const photoTask = TaskModel(id: 't1', title: 'Make the bed', requiresPhoto: true);
    const plainTask = TaskModel(id: 't2', title: 'Feed the cat');

    test('photo proof applies only while the admin has Premium', () async {
      await seed(DateTime.now().add(const Duration(days: 7)));
      expect(db.householdHasPremium, isTrue);
      expect(db.needsPhoto(photoTask), isTrue);
      expect(db.needsPhoto(plainTask), isFalse);
    });

    test('without Premium (or once it has ended) photo tasks finish without a photo', () async {
      await seed(DateTime.now().subtract(const Duration(minutes: 1)));
      expect(db.householdHasPremium, isFalse);
      expect(db.needsPhoto(photoTask), isFalse);
    });

    test('premiumUntil is not part of Household.toFirestore', () async {
      final h = Household(id: 'h', name: 'x', memberIds: const [], premiumUntil: DateTime.now());
      expect(h.toFirestore().containsKey('premiumUntil'), isFalse);
    });
  });
}
