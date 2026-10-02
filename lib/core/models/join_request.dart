import 'package:cloud_firestore/cloud_firestore.dart';

import 'user.dart';

/// Someone asked to join a household with its invite code:
/// `households/{householdId}/joinRequests/{userId}`.
///
/// Nobody joins a household on their own - the household's admin approves
/// (adds them to `memberIds`) or declines (deletes the request). The request
/// carries the requester's name/email/role so the admin can see who it is
/// before they're a member (and so before their profile is readable).
class JoinRequest {
  const JoinRequest({
    required this.userId,
    required this.householdId,
    required this.name,
    required this.email,
    required this.role,
    this.avatarEmoji = '🙂',
    this.householdName,
    this.requestedAt,
  });

  final String userId;
  final String householdId;
  final String name;
  final String email;
  final UserRole role;
  final String avatarEmoji;

  /// Copied from the household so the requester can show "Waiting for
  /// approval from <household>" without another read.
  final String? householdName;
  final DateTime? requestedAt;

  factory JoinRequest.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return JoinRequest(
      userId: doc.id,
      householdId: data['householdId'] as String? ?? doc.reference.parent.parent?.id ?? '',
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: UserRole.values.firstWhere(
        (r) => r.name == data['role'],
        orElse: () => UserRole.child,
      ),
      avatarEmoji: data['avatarEmoji'] as String? ?? '🙂',
      householdName: data['householdName'] as String?,
      requestedAt: (data['requestedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'householdId': householdId,
      'name': name,
      'email': email,
      'role': role.name,
      'avatarEmoji': avatarEmoji,
      'householdName': householdName,
      'requestedAt': requestedAt == null ? null : Timestamp.fromDate(requestedAt!),
    };
  }
}
