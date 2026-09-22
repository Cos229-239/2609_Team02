import 'package:cloud_firestore/cloud_firestore.dart';

/// Broad category of reward, so the UI can pick a sensible icon/color and
/// so redemption logic can differ (e.g. screen-time rewards might need
/// parental confirmation on a device, while a badge is granted instantly).
enum RewardType { points, screenTime, activity, treat, badge }

/// One item in a household's reward store. Parents create/edit/delete
/// these (see [DatabaseService.addReward] and friends); children spend
/// coins earned from approved tasks to redeem them (see
/// [DatabaseService.redeemReward]), which records a [Redemption].
class Reward {
  const Reward({
    required this.id,
    required this.title,
    required this.type,
    this.description = '',
    this.icon = '⭐',
    this.coinCost = 0,
  });

  final String id;
  final String title;
  final String description;
  final String icon;
  final RewardType type;

  /// How many coins this reward costs to redeem from the store.
  final int coinCost;

  Reward copyWith({
    String? title,
    String? description,
    String? icon,
    RewardType? type,
    int? coinCost,
  }) {
    return Reward(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      type: type ?? this.type,
      coinCost: coinCost ?? this.coinCost,
    );
  }

  /// Seeded into a household's `rewards` subcollection when it's created,
  /// so every new family starts out with a sample catalog to work with.
  static const List<Reward> defaultCatalog = [
    Reward(
      id: 'reward-xp',
      title: '50 Bonus Coins',
      description: 'A little pocket-money style bonus.',
      icon: '⭐',
      type: RewardType.points,
      coinCost: 50,
    ),
    Reward(
      id: 'reward-screentime',
      title: '+30 Minutes Game Time',
      description: 'Extra screen time, parent-approved.',
      icon: '🎮',
      type: RewardType.screenTime,
      coinCost: 100,
    ),
    Reward(
      id: 'reward-outing',
      title: 'Fun Day Out',
      description: 'A family outing of your choice.',
      icon: '🌳',
      type: RewardType.activity,
      coinCost: 200,
    ),
    Reward(
      id: 'reward-treat',
      title: 'Sweet Treat of Choice',
      description: 'Pick your favorite treat.',
      icon: '🍬',
      type: RewardType.treat,
      coinCost: 150,
    ),
  ];

  factory Reward.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Reward(
      id: doc.id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      icon: data['icon'] as String? ?? '⭐',
      type: RewardType.values.firstWhere(
        (t) => t.name == data['type'],
        orElse: () => RewardType.points,
      ),
      coinCost: data['coinCost'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'icon': icon,
      'type': type.name,
      'coinCost': coinCost,
    };
  }
}
