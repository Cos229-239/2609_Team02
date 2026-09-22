import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/reward.dart';
import 'package:famotive/core/services/database_service.dart';

void main() {
  group('DatabaseService reward store', () {
    late FakeFirebaseFirestore firestore;
    late DatabaseService databaseService;

    const householdId = 'household-1';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      databaseService = DatabaseService(firestore: firestore);
      databaseService.bindHousehold(householdId);
    });

    Future<String> addReward(Reward reward) async {
      await databaseService.addReward(reward);
      final snapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('rewards')
          .get();
      return snapshot.docs.first.id;
    }

    test('redeeming a reward deducts coins and records a redemption', () async {
      await firestore.collection('users').doc('child-1').set({
        'coins': 100,
        'householdId': householdId,
      });

      const reward = Reward(
        id: 'placeholder',
        title: 'Movie Night',
        type: RewardType.activity,
        coinCost: 60,
      );
      final rewardId = await addReward(reward);

      await databaseService.redeemReward(rewardId: rewardId, childId: 'child-1');

      final child = await firestore.collection('users').doc('child-1').get();
      expect(child.data()?['coins'], 40);

      final redemptions = await firestore
          .collection('households')
          .doc(householdId)
          .collection('redemptions')
          .get();

      expect(redemptions.docs, hasLength(1));
      expect(redemptions.docs.first.data()['rewardTitle'], 'Movie Night');
      expect(redemptions.docs.first.data()['coinCost'], 60);
      expect(redemptions.docs.first.data()['childId'], 'child-1');
      expect(redemptions.docs.first.data()['acknowledgedByParent'], isFalse);
    });

    test('redeeming without enough coins throws and changes nothing', () async {
      await firestore.collection('users').doc('child-1').set({
        'coins': 10,
        'householdId': householdId,
      });

      const reward = Reward(
        id: 'placeholder',
        title: 'Movie Night',
        type: RewardType.activity,
        coinCost: 60,
      );
      final rewardId = await addReward(reward);

      await expectLater(
        databaseService.redeemReward(rewardId: rewardId, childId: 'child-1'),
        throwsException,
      );

      final child = await firestore.collection('users').doc('child-1').get();
      expect(child.data()?['coins'], 10);

      final redemptions = await firestore
          .collection('households')
          .doc(householdId)
          .collection('redemptions')
          .get();
      expect(redemptions.docs, isEmpty);
    });

    test('acknowledgeAllRedemptions marks every pending redemption seen', () async {
      await firestore.collection('users').doc('child-1').set({
        'coins': 100,
        'householdId': householdId,
      });
      const reward = Reward(
        id: 'placeholder',
        title: 'Treat',
        type: RewardType.treat,
        coinCost: 20,
      );
      final rewardId = await addReward(reward);

      await databaseService.redeemReward(rewardId: rewardId, childId: 'child-1');
      await databaseService.redeemReward(rewardId: rewardId, childId: 'child-1');

      // Allow the Firestore listener in DatabaseService to receive the
      // new redemption docs.
      await Future<void>.delayed(Duration.zero);

      expect(databaseService.unacknowledgedRedemptions, hasLength(2));

      await databaseService.acknowledgeAllRedemptions();
      await Future<void>.delayed(Duration.zero);

      expect(databaseService.unacknowledgedRedemptions, isEmpty);
    });

    test('updateReward overwrites the stored fields', () async {
      const reward = Reward(
        id: 'placeholder',
        title: 'Old Title',
        type: RewardType.treat,
        coinCost: 10,
      );
      final rewardId = await addReward(reward);

      await databaseService.updateReward(
        rewardId,
        reward.copyWith(title: 'New Title', coinCost: 25),
      );

      final updated = await firestore
          .collection('households')
          .doc(householdId)
          .collection('rewards')
          .doc(rewardId)
          .get();

      expect(updated.data()?['title'], 'New Title');
      expect(updated.data()?['coinCost'], 25);
    });

    test('deleteReward removes it from the catalog', () async {
      const reward = Reward(
        id: 'placeholder',
        title: 'Doomed Reward',
        type: RewardType.treat,
        coinCost: 10,
      );
      final rewardId = await addReward(reward);

      await databaseService.deleteReward(rewardId);

      final snapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('rewards')
          .get();
      expect(snapshot.docs, isEmpty);
    });

    test('rewardById finds a synced reward by id, or null if unknown', () async {
      const reward = Reward(
        id: 'placeholder',
        title: 'Pinnable Reward',
        type: RewardType.treat,
        coinCost: 30,
      );
      final rewardId = await addReward(reward);
      await Future<void>.delayed(Duration.zero);

      expect(databaseService.rewardById(rewardId)?.title, 'Pinnable Reward');
      expect(databaseService.rewardById('does-not-exist'), isNull);
    });

    test('setPinnedReward stores and clears a pinned goal', () async {
      await firestore.collection('users').doc('child-1').set({
        'coins': 0,
        'householdId': householdId,
      });

      await databaseService.setPinnedReward('child-1', 'reward-xp');
      var child = await firestore.collection('users').doc('child-1').get();
      expect(child.data()?['pinnedRewardId'], 'reward-xp');

      await databaseService.setPinnedReward('child-1', null);
      child = await firestore.collection('users').doc('child-1').get();
      expect(child.data()?['pinnedRewardId'], isNull);
    });
  });
}
