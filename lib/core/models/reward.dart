import 'package:cloud_firestore/cloud_firestore.dart';

/// Broad category of reward, so the UI can pick a sensible icon/color and
/// so redemption logic can differ (e.g. screen-time rewards might need
/// parental confirmation on a device, while a badge is granted instantly).
enum RewardType { points, screenTime, activity, treat, badge }

class Reward {
  const Reward({
    required this.id,
    required this.title,
    required this.type,
    this.description = '',
    this.icon = '⭐',
    this.xpCost = 0,
  });

  final String id;
  final String title;
  final String description;
  final String icon;
  final RewardType type;

  /// How much XP this reward costs to redeem. 0 for rewards that are simply
  /// earned alongside a task (like the flat "50 XP" reward itself).
  final int xpCost;

  /// Seeded into a household's `rewards` subcollection when it's created,
  /// so every new family starts out with a sample catalog to work with.
  static const List<Reward> defaultCatalog = [
    Reward(
      id: 'reward-xp',
      title: '50 XP',
      description: 'Earn 50 points',
      icon: '⭐',
      type: RewardType.points,
      xpCost: 50,
    ),
    Reward(
      id: 'reward-screentime',
      title: '+30 Minutes Game Time',
      description: 'Earn 100 points',
      icon: '🎮',
      type: RewardType.screenTime,
      xpCost: 100,
    ),
    Reward(
      id: 'reward-outing',
      title: 'Fun Day Out',
      description: 'Earn 200 points',
      icon: '🌳',
      type: RewardType.activity,
      xpCost: 200,
    ),
    Reward(
      id: 'reward-treat',
      title: 'Extra Sweet Treat of Choice',
      description: 'Earn 150 points',
      icon: '🍬',
      type: RewardType.treat,
      xpCost: 150,
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
      xpCost: data['xpCost'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'icon': icon,
      'type': type.name,
      'xpCost': xpCost,
    };
  }
}
