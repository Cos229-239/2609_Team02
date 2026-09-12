import 'package:cloud_firestore/cloud_firestore.dart';

class Household {
  const Household({
    required this.id,
    required this.name,
    required this.memberIds,
    this.inviteCode,
  });

  final String id;
  final String name;
  final List<String> memberIds;

  /// Code parents share with the other parent/guardian (or their kids) so
  /// they can join this household from the register screen.
  final String? inviteCode;

  factory Household.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Household(
      id: doc.id,
      name: data['name'] as String? ?? '',
      memberIds: List<String>.from(data['memberIds'] as List? ?? const []),
      inviteCode: data['inviteCode'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'memberIds': memberIds,
      'inviteCode': inviteCode,
    };
  }
}
