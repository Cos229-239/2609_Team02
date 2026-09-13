import '../../../core/models/household.dart';
import '../../../core/services/database_service.dart';

/// Household-specific read/write helpers, kept separate from the generic
/// [DatabaseService] so household concerns (renaming the household,
/// inviting members) have an obvious home as they grow. Currently a thin
/// pass-through over the in-memory demo data.
class HouseholdService {
  HouseholdService(this._db);

  final DatabaseService _db;

  Household? get currentHousehold => _db.household;

  int get memberCount => _db.familyMembers.length;

  // TODO: implement invite-code generation/redemption once household
  // membership is backed by a real data source.
}
