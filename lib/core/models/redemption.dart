import 'package:cloud_firestore/cloud_firestore.dart';

/// A record of a child redeeming one [Reward] from the household's store.
/// Written by [DatabaseService.redeemReward].
class Redemption {
  const Redemption({
    required this.id,
    required this.rewardId,
    required this.rewardTitle,
    required this.rewardIcon,
    required this.childId,
    required this.coinCost,
    required this.redeemedAt,
    this.acknowledgedByParent = false,
  });

  final String id;
  final String rewardId;
  final String rewardTitle;
  final String rewardIcon;
  final String childId;
  final int coinCost;
  final DateTime redeemedAt;

  /// Set once a parent has seen this redemption.
  final bool acknowledgedByParent;

  factory Redemption.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Redemption(
      id: doc.id,
      rewardId: data['rewardId'] as String? ?? '',
      rewardTitle: data['rewardTitle'] as String? ?? '',
      rewardIcon: data['rewardIcon'] as String? ?? '⭐',
      childId: data['childId'] as String? ?? '',
      coinCost: data['coinCost'] as int? ?? 0,
      redeemedAt: (data['redeemedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      acknowledgedByParent: data['acknowledgedByParent'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'rewardId': rewardId,
      'rewardTitle': rewardTitle,
      'rewardIcon': rewardIcon,
      'childId': childId,
      'coinCost': coinCost,
      'redeemedAt': Timestamp.fromDate(redeemedAt),
      'acknowledgedByParent': acknowledgedByParent,
    };
  }
}
