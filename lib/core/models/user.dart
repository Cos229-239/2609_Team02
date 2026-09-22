import 'package:cloud_firestore/cloud_firestore.dart';

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

  final String? householdId;

  /// Id of the reward this child has pinned as a goal, or null.
  final String? pinnedRewardId;

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
      householdId: householdId,
      pinnedRewardId: clearPinnedRewardId ? null : (pinnedRewardId ?? this.pinnedRewardId),
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
    };
  }
}
