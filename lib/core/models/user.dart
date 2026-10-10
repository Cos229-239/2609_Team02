import 'package:cloud_firestore/cloud_firestore.dart';

import 'premium_status.dart';

/// The role a household member has inside a family. Drives which
/// screens/actions are available (e.g. only parents can assign tasks).
enum UserRole { parent, child }

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.avatarEmoji = '🙂',
    this.phoneNumber,
    this.age,
    this.xp = 0,
    this.coins = 0,
    this.householdId,
    this.pinnedRewardId,
    this.pushNotificationsEnabled = true,
    this.pendingHouseholdIds = const [],
    this.createdByParentId,
    this.premium = PremiumStatus.none,
  });

  final String id;
  final String name;
  final String email;
  final UserRole role;

  /// Placeholder avatar (an emoji) until real avatar images/uploads exist.
  final String avatarEmoji;
  final String? phoneNumber;
  final int? age;

  /// Leveling/leaderboard total: never spent.
  final int xp;

  /// Spendable currency, earned from tasks and spent on rewards.
  final int coins;

  /// The household this user is currently looking at (their "active"
  /// household). Membership itself lives in `households/{id}.memberIds`,
  /// and a user can belong to several; XP and coins stay on this profile,
  /// so they carry across every household.
  final String? householdId;

  /// Households this user asked to join with an invite code and that the
  /// household's admin hasn't approved yet.
  final List<String> pendingHouseholdIds;

  /// Set on child accounts a parent created from inside the app.
  final String? createdByParentId;

  /// Id of the reward this child has pinned as a goal, or null.
  final String? pinnedRewardId;

  /// Opt-in for push notifications (Settings > Notifications). Read by the
  /// Cloud Functions in functions/src/index.ts before sending anything.
  final bool pushNotificationsEnabled;

  /// Famotive Premium subscription (server-written; never saved by the app,
  /// so it isn't in [toFirestore]).
  final PremiumStatus premium;

  bool get isParent => role == UserRole.parent;
  bool get isChild => role == UserRole.child;

  AppUser copyWith({
    String? name,
    String? avatarEmoji,
    int? age,
    String? phoneNumber,
    String? email,
    int? xp,
    int? coins,
    String? pinnedRewardId,
    bool clearPinnedRewardId = false,
    bool? pushNotificationsEnabled,
    String? householdId,
    bool clearHouseholdId = false,
    List<String>? pendingHouseholdIds,
  }) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      age: age ?? this.age,
      xp: xp ?? this.xp,
      coins: coins ?? this.coins,
      householdId: clearHouseholdId ? null : (householdId ?? this.householdId),
      pinnedRewardId: clearPinnedRewardId ? null : (pinnedRewardId ?? this.pinnedRewardId),
      pushNotificationsEnabled: pushNotificationsEnabled ?? this.pushNotificationsEnabled,
      pendingHouseholdIds: pendingHouseholdIds ?? this.pendingHouseholdIds,
      createdByParentId: createdByParentId,
      premium: premium,
    );
  }

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return AppUser(
      id: doc.id,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: UserRole.values.firstWhere(
        (r) => r.name == data['role'],
        orElse: () => UserRole.child,
      ),
      phoneNumber: data['phoneNumber'] as String?,
      avatarEmoji: data['avatarEmoji'] as String? ?? '🙂',
      age: data['age'] as int?,
      xp: data['xp'] as int? ?? 0,
      coins: data['coins'] as int? ?? 0,
      householdId: data['householdId'] as String?,
      pinnedRewardId: data['pinnedRewardId'] as String?,
      pushNotificationsEnabled: data['pushNotificationsEnabled'] as bool? ?? true,
      pendingHouseholdIds: List<String>.from(data['pendingHouseholdIds'] as List? ?? const []),
      createdByParentId: data['createdByParentId'] as String?,
      premium: PremiumStatus.fromMap(data['premium']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'role': role.name,
      'avatarEmoji': avatarEmoji,
      'phoneNumber': phoneNumber,
      'age': age,
      'xp': xp,
      'coins': coins,
      'householdId': householdId,
      'pinnedRewardId': pinnedRewardId,
      'pushNotificationsEnabled': pushNotificationsEnabled,
      'pendingHouseholdIds': pendingHouseholdIds,
      if (createdByParentId != null) 'createdByParentId': createdByParentId,
    };
  }
}
