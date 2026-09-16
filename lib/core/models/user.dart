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
    this.householdId,
  });

  final String id;
  final String name;
  final String email;
  final UserRole role;

  /// Placeholder avatar (an emoji) until real avatar images/uploads exist.
  final String avatarEmoji;
  final String? phoneNumber;
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
      phoneNumber: data['phoneNumber'] as String?,
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
      'phoneNumber': phoneNumber,
      'age': age,
      'xp': xp,
      'householdId': householdId,
    };
  }
}
