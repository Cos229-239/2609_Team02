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
    this.age,
    this.xp = 0,
    this.householdId,
  });

  final String id;
  final String name;
  final String email;
  final UserRole role;

  /// Placeholder avatar (an emoji) until real avatar images/uploads exist.
  final String avatarEmoji;
  final int? age;
  final int xp;
  final String? householdId;

  bool get isParent => role == UserRole.parent;
  bool get isChild => role == UserRole.child;

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
      avatarEmoji: data['avatarEmoji'] as String? ?? '🙂',
      age: data['age'] as int?,
      xp: data['xp'] as int? ?? 0,
      householdId: data['householdId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'role': role.name,
      'avatarEmoji': avatarEmoji,
      'age': age,
      'xp': xp,
      'householdId': householdId,
    };
  }

  AppUser copyWith({
    String? name,
    String? email,
    UserRole? role,
    String? avatarEmoji,
    int? age,
    int? xp,
    String? householdId,
  }) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      age: age ?? this.age,
      xp: xp ?? this.xp,
      householdId: householdId ?? this.householdId,
    );
  }
}
