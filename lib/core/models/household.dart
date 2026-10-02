import 'package:cloud_firestore/cloud_firestore.dart';

class Household {
  const Household({
    required this.id,
    required this.name,
    required this.memberIds,
    this.ownerId,
    this.inviteCode,
    this.timezone,
  });

  final String id;
  final String name;

  /// Everyone in this household (parents/adults and children). This list is
  /// the source of truth for membership: a user can be in several
  /// households, and `users/{uid}.householdId` only records which one they
  /// are currently looking at.
  final List<String> memberIds;

  /// The household's admin: whoever created it (or the first member, for
  /// households created before admins existed). Only the admin can approve
  /// people who ask to join with the invite code, remove other adults, or
  /// hand the admin role to another parent.
  final String? ownerId;

  /// Code to share with family. Entering it sends a join request that the
  /// admin has to approve - it never adds anyone on its own.
  final String? inviteCode;

  /// IANA time zone (e.g. "America/Chicago"). Reminders and repeating tasks
  /// roll over at 9 AM in this zone. Set from a member's device.
  final String? timezone;

  bool isAdmin(String? userId) => userId != null && ownerId == userId;

  bool hasMember(String? userId) => userId != null && memberIds.contains(userId);

  factory Household.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Household(
      id: doc.id,
      name: data['name'] as String? ?? '',
      memberIds: List<String>.from(data['memberIds'] as List? ?? const []),
      ownerId: data['ownerId'] as String?,
      inviteCode: data['inviteCode'] as String?,
      timezone: data['timezone'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'memberIds': memberIds,
      'ownerId': ownerId,
      'inviteCode': inviteCode,
      'timezone': timezone,
    };
  }
}
