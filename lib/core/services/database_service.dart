import 'package:flutter/foundation.dart';

import '../models/household.dart';
import '../models/reward.dart';
import '../models/task.dart';
import '../models/user.dart';

/// In-memory stand-in for persistent storage (Firestore/local DB)
/// Seeded with demo data that mirrors the lo-fidelity
/// wireframes so every screen has something real to show and the sample
/// flow (assign → complete → approve → earn) actually mutates state.
///
/// Replace the bodies of these methods with real persistence calls later;
/// the shape of the API (methods + ChangeNotifier so widgets rebuild) is
/// meant to stay stable.
class DatabaseService extends ChangeNotifier {
  DatabaseService() {
    _seedDemoData();
  }

  late Household household;
  final List<AppUser> familyMembers = [];
  final List<TaskModel> tasks = [];
  final List<Reward> availableRewards = [];

  void _seedDemoData() {
    household = const Household(
      id: 'household-1',
      name: 'The Full Sail Family',
      memberIds: ['user-parent-1', 'user-child-alex'],
    );

    familyMembers.addAll(const [
      AppUser(
        id: 'user-parent-1',
        name: 'Jamie',
        email: 'jamie@famotive.app',
        role: UserRole.parent,
        avatarEmoji: '👩',
        householdId: 'household-1',
      ),
      AppUser(
        id: 'user-child-alex',
        name: 'Alex',
        email: 'alex@famotive.app',
        role: UserRole.child,
        avatarEmoji: '🧑',
        age: 9,
        xp: 120,
        householdId: 'household-1',
      ),
    ]);

    tasks.addAll(const [
      TaskModel(
        id: 'task-1',
        title: 'Make Bed',
        description: 'Keep your room tidy!',
        icon: '🛏️',
        assignedToUserId: 'user-child-alex',
        rewardXp: 50,
        status: TaskStatus.approved,
      ),
      TaskModel(
        id: 'task-2',
        title: 'Clean Room',
        description: 'Make your room sparkle.',
        icon: '🧹',
        assignedToUserId: 'user-child-alex',
        rewardXp: 50,
        status: TaskStatus.pending,
      ),
      TaskModel(
        id: 'task-3',
        title: 'Sweep/Mop Kitchen',
        description: 'Help keep the kitchen clean.',
        icon: '🧽',
        assignedToUserId: 'user-child-alex',
        rewardXp: 50,
        status: TaskStatus.pending,
      ),
    ]);

    availableRewards.addAll(const [
      Reward(
        id: 'reward-xp',
        title: '50 XP',
        description: 'Earn 50 points',
        icon: '⭐',
        type: RewardType.points,
        xpCost: 50,
      ),
      Reward(
        id: 'reward-screentime',
        title: '+30 Minutes Game Time',
        description: 'Earn 100 points',
        icon: '🎮',
        type: RewardType.screenTime,
        xpCost: 100,
      ),
      Reward(
        id: 'reward-outing',
        title: 'Fun Day Out',
        description: 'Earn 200 points',
        icon: '🌳',
        type: RewardType.activity,
        xpCost: 200,
      ),
      Reward(
        id: 'reward-treat',
        title: 'Extra Sweet Treat of Choice',
        description: 'Earn 150 points',
        icon: '🍬',
        type: RewardType.treat,
        xpCost: 150,
      ),
    ]);
  }

  // --- Queries ---------------------------------------------------------

  List<AppUser> get children =>
      familyMembers.where((m) => m.isChild).toList(growable: false);

  AppUser? userById(String id) {
    for (final member in familyMembers) {
      if (member.id == id) return member;
    }
    return null;
  }

  List<TaskModel> tasksForUser(String userId) =>
      tasks.where((t) => t.assignedToUserId == userId).toList(growable: false);

  // --- Mutations ---------------------------------------------------------

  void addTask(TaskModel task) {
    tasks.add(task);
    notifyListeners();
  }

  void removeTask(String taskId) {
    tasks.removeWhere((t) => t.id == taskId);
    notifyListeners();
  }

  /// Child marks a task done — moves it to `completed`, awaiting approval.
  TaskModel completeTask(String taskId) {
    final index = tasks.indexWhere((t) => t.id == taskId);
    final updated = tasks[index].copyWith(status: TaskStatus.completed);
    tasks[index] = updated;
    notifyListeners();
    return updated;
  }

  /// Parent approves a completed task — grants XP to the child.
  void approveTask(String taskId) {
    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;
    final task = tasks[index];
    tasks[index] = task.copyWith(status: TaskStatus.approved);

    final userIndex =
        familyMembers.indexWhere((m) => m.id == task.assignedToUserId);
    if (userIndex != -1) {
      final user = familyMembers[userIndex];
      familyMembers[userIndex] = user.copyWith(xp: user.xp + task.rewardXp);
    }
    notifyListeners();
  }
}
