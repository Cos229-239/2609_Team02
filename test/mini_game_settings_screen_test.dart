import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:famotive/core/models/mini_game.dart';
import 'package:famotive/core/models/user.dart';
import 'package:famotive/core/services/database_service.dart';
import 'package:famotive/core/services/mini_game_service.dart';
import 'package:famotive/features/minigames/screens/mini_game_host_screen.dart';
import 'package:famotive/features/minigames/screens/mini_game_settings_screen.dart';
import 'package:famotive/features/minigames/widgets/mini_games_store_section.dart';

void main() {
  const householdId = 'h1';
  late FakeFirebaseFirestore firestore;

  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  setUp(() => firestore = FakeFirebaseFirestore());

  testWidgets('a parent gives one child easier Match Pairs; the family defaults stay', (tester) async {
    tallScreen(tester);
    const parent = AppUser(id: 'p', name: 'Pat', email: 'p@x', role: UserRole.parent, householdId: householdId);
    const kid = AppUser(id: 'kid', name: 'Ava', email: 'k@x', role: UserRole.child, householdId: householdId);
    final service = MiniGameService(firestore: firestore)..bind(parent);
    final db = DatabaseService(firestore: firestore, deviceTimeZone: () async => null)..familyMembers = [parent, kid];

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<MiniGameService>.value(value: service),
        ChangeNotifierProvider<DatabaseService>.value(value: db),
      ],
      child: const MaterialApp(home: MiniGameSettingsScreen(initialChildId: 'kid')),
    ));
    await tester.pump();
    expect(find.text('Use Family-Wide Settings'), findsOneWidget);

    await tester.tap(find.text('Use Family-Wide Settings'));
    await tester.pump();
    await tester.tap(find.text('Match Pairs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Easy'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('minigame-settings-save')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    final override = await firestore.collection('households').doc(householdId).collection('miniGameSettings').doc('kid').get();
    expect(override.exists, isTrue);
    expect(override.data()!['matchPairs'], {'pairs': 4, 'maxMisses': 4});
    final family = await firestore.collection('households').doc(householdId).collection('miniGameSettings').doc('household').get();
    expect(family.exists, isFalse, reason: 'household defaults untouched');
    expect(service.settingsFor('kid').matchPairs.pairs, 4);
  });

  testWidgets('the Reward Store lists every game and launches a casual round', (tester) async {
    tallScreen(tester);
    const kid = AppUser(id: 'kid', name: 'Ava', email: 'k@x', role: UserRole.child, householdId: householdId);
    final service = MiniGameService(firestore: firestore)..bind(kid);
    await tester.pumpWidget(ChangeNotifierProvider<MiniGameService>.value(
      value: service,
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: MiniGamesStoreSection(childId: 'kid')))),
    ));
    for (final id in MiniGameId.values) {
      expect(find.text(id.title), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('store-game-memoryRun')));
    await tester.pumpAndSettle();
    final host = tester.widget<MiniGameHostScreen>(find.byType(MiniGameHostScreen));
    expect(host.isRewarded, isFalse, reason: 'store games are practice rounds, never rewarded');
    expect(find.textContaining('Practice round'), findsOneWidget);
    expect((await firestore.collectionGroup('miniGameSessions').get()).size, 0);
  });
}
