import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../core/models/task.dart';
import '../../core/services/database_service.dart';

Future<bool> startTaskCompletion(BuildContext context, TaskModel task, {bool celebrate = false}) async {
  final navigator = Navigator.of(context);
  // Photo proof only applies while the household has Premium.
  if (context.read<DatabaseService>().needsPhoto(task)) {
    final Object? done = await navigator.pushNamed(AppRoutes.taskProof, arguments: task.id);
    return done == true;
  }
  await context.read<DatabaseService>().completeTask(task.id);
  if (celebrate) {
    await navigator.pushReplacementNamed(AppRoutes.taskCompletion, arguments: task.id);
  }
  return true;
}
