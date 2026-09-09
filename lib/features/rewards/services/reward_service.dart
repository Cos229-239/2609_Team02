import '../../../core/models/reward.dart';
import '../../../core/services/database_service.dart';

/// Reward-specific helpers layered over [DatabaseService]. Currently just
/// exposes the catalog of available rewards; grows to support custom,
/// parent-defined rewards later.
class RewardService {
  RewardService(this._db);

  final DatabaseService _db;

  List<Reward> get availableRewards => _db.availableRewards;
}
