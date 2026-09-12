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

  /// Code parents share with the other parent/guardian (or older kids) to
  /// join the household. Placeholder for future invite flow.
  final String? inviteCode;
}
