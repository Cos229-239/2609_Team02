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
}
