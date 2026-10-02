import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';

/// App-bar title: the active household's name. Tapping it opens a sheet to
/// switch between households or manage them.
class HouseholdSwitcher extends StatelessWidget {
  const HouseholdSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DatabaseService>();
    final name = db.household?.name ?? 'Famotive';

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _showSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  void _showSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final db = sheetContext.watch<DatabaseService>();
        final auth = sheetContext.read<AuthService>();
        final activeId = auth.currentUser?.householdId;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final h in db.myHouseholds)
                ListTile(
                  leading: Icon(h.id == activeId ? Icons.check_circle : Icons.home_outlined,
                      color: h.id == activeId ? Theme.of(sheetContext).colorScheme.primary : null),
                  title: Text(h.name),
                  subtitle: h.isAdmin(auth.currentUser?.id) ? const Text('Admin') : null,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    if (h.id != activeId) auth.switchHousehold(h.id);
                  },
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Manage households'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).pushNamed(AppRoutes.households);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
