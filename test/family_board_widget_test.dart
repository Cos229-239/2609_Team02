import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:famotive/app/routes.dart';
import 'package:famotive/core/models/family_milestone.dart';
import 'package:famotive/core/models/progress_event.dart';
import 'package:famotive/core/models/user.dart';
import 'package:famotive/core/services/auth_service.dart';
import 'package:famotive/core/services/database_service.dart';
import 'package:famotive/core/services/milestone_service.dart';
import 'package:famotive/features/milestones/board_layout.dart';
import 'package:famotive/features/milestones/screens/approval_journey_screen.dart';
import 'package:famotive/features/milestones/screens/family_board_screen.dart';
import 'package:famotive/features/milestones/widgets/family_board.dart';
import 'package:famotive/features/milestones/widgets/family_goal_card.dart';
import 'package:famotive/features/milestones/widgets/progress_event_presenter.dart';

void main() {
  group('BoardLayout', () {
    test('lays out boardLength + 1 spaces on a serpentine path inside the width', () {
      final layout = BoardLayout.compute(boardLength: 20, width: 400);
      expect(layout.spaceCount, 21);
      expect(layout.columns, 5);
      for (final c in layout.centers) {
        expect(c.dx, inInclusiveRange(0, 400));
        expect(c.dy, inInclusiveRange(0, layout.size.height));
      }
      // Row 0 goes left→right, row 1 right→left.
      expect(layout.centers[0].dx < layout.centers[4].dx, isTrue);
      expect(layout.centers[5].dx > layout.centers[9].dx, isTrue);
      expect(layout.centers[5].dx, layout.centers[4].dx);
    });

    test('narrow phones get fewer columns; pointAt interpolates and clamps', () {
      final layout = BoardLayout.compute(boardLength: 10, width: 320);
      expect(layout.columns, 4);
      final mid = layout.pointAt(0.5);
      expect(mid.dx, (layout.centers[0].dx + layout.centers[1].dx) / 2);
      expect(layout.pointAt(-3), layout.centers.first);
      expect(layout.pointAt(99), layout.centers.last);
    });
  });

  testWidgets('FamilyBoard animates the piece and reports when it arrives', (tester) async {
    var done = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FamilyBoard(boardLength: 10, position: 3, animateFrom: 1, onMoveDone: () => done++),
        ),
      ),
    ));
    expect(
      find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Family board: space 3 of 10'),
      findsOneWidget,
    );
    expect(done, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(done, 1);
  });

  group('screens', () {
    late FakeFirebaseFirestore firestore;
    late MilestoneService milestones;

    Future<AuthService> signIn(UserRole role) async {
      final user = AppUser(id: 'u1', name: 'Sam', email: 's@x', role: role, householdId: 'h1');
      await firestore.collection('users').doc('u1').set(user.toFirestore());
      final auth = AuthService(
        auth: MockFirebaseAuth(mockUser: MockUser(uid: 'u1', email: 's@x'), signedIn: true),
        firestore: firestore,
      );
      await auth.tryRestoreSession();
      milestones = MilestoneService(firestore: firestore)..bind(auth.currentUser);
      return auth;
    }

    Widget app(AuthService auth, Widget home) => MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<DatabaseService>(create: (_) => DatabaseService(firestore: firestore)),
            ChangeNotifierProvider<MilestoneService>.value(value: milestones),
          ],
          child: MaterialApp(home: home, onGenerateRoute: AppRoutes.onGenerateRoute),
        );

    Future<void> addGoal({int position = 8}) async {
      final now = DateTime.now();
      await firestore.collection('households').doc('h1').collection('milestones').doc('m1').set({
        ...FamilyMilestone(
          id: 'm1',
          title: 'Movie night',
          rewardTitle: 'Movies & popcorn',
          rewardIcon: '🍿',
          startsAt: now.subtract(const Duration(days: 1)),
          endsAt: now.add(const Duration(days: 10)),
          position: position,
        ).toFirestore(),
      });
    }

    setUp(() => firestore = FakeFirebaseFirestore());

    /// A tall phone so whole screens are built (ListViews build lazily).
    void tallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(1170, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    testWidgets('Home card shows the shared progress', (tester) async {
      final auth = await signIn(UserRole.child);
      await addGoal();
      await tester.pumpWidget(app(auth, const Scaffold(body: FamilyGoalCard(isParent: false))));
      await tester.pump();
      expect(find.text('Movie night'), findsOneWidget);
      expect(find.text('8 of 20 spaces'), findsOneWidget);
    });

    testWidgets('parents without a goal are invited to create one; children see nothing', (tester) async {
      final parent = await signIn(UserRole.parent);
      await tester.pumpWidget(app(parent, const Scaffold(body: FamilyGoalCard(isParent: true))));
      await tester.pump();
      expect(find.text('Start a Family Goal'), findsOneWidget);

      await tester.pumpWidget(app(parent, const Scaffold(body: FamilyGoalCard(isParent: false))));
      await tester.pump();
      expect(find.text('Start a Family Goal'), findsNothing);
    });

    testWidgets('board screen: empty state for a child, board + progress with a goal', (tester) async {
      final auth = await signIn(UserRole.child);
      await tester.pumpWidget(app(auth, const FamilyBoardScreen()));
      await tester.pump();
      expect(find.text('No family goal yet'), findsOneWidget);
      expect(find.text('Create a Family Goal'), findsNothing);

      await addGoal(position: 5);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('5 of 20 spaces'), findsOneWidget);
      expect(find.byType(FamilyBoard), findsOneWidget);
      expect(find.byTooltip('Manage family goal'), findsNothing, reason: 'children have no parent controls');
    });

    testWidgets('approval journey animates the move and offers the next step', (tester) async {
      tallScreen(tester);
      final auth = await signIn(UserRole.child);
      await addGoal(position: 6);
      final events = [
        ProgressEvent(taskId: 'a', childId: 'u1', taskTitle: 'Dishes', createdAt: DateTime(2026), milestoneId: 'm1',
            fromPosition: 4, toPosition: 5, boardLength: 20),
        ProgressEvent(taskId: 'b', childId: 'u1', taskTitle: 'Laundry', createdAt: DateTime(2026), milestoneId: 'm1',
            fromPosition: 5, toPosition: 6, boardLength: 20),
      ];
      var continued = false;
      await tester.pumpWidget(app(
        auth,
        ApprovalJourneyScreen(
          events: events,
          afterBoardLabel: 'Play your bonus game!',
          afterBoard: (_) async => continued = true,
        ),
      ));
      await tester.pump();
      expect(find.text('2 tasks approved!'), findsOneWidget);
      expect(find.textContaining('moved 2 spaces'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('journey-continue')));
      expect(continued, isTrue);
    });

    testWidgets('the presenter shows a batch of approvals exactly once', (tester) async {
      tallScreen(tester);
      final auth = await signIn(UserRole.child);
      await addGoal(position: 1);
      await firestore.collection('households').doc('h1').collection('progressEvents').doc('t1').set(
            ProgressEvent(taskId: 't1', childId: 'u1', taskTitle: 'Dishes', createdAt: DateTime(2026),
                milestoneId: 'm1', fromPosition: 0, toPosition: 1, boardLength: 20)
                .toFirestore(),
          );
      await tester.pumpWidget(app(auth, const Scaffold(body: ProgressEventPresenter(child: Text('tabs')))));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ApprovalJourneyScreen), findsOneWidget);
      expect(milestones.unpresentedEvents, isEmpty);

      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('journey-done')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ApprovalJourneyScreen), findsNothing);
      expect(find.text('tabs'), findsOneWidget);
      final stored = await firestore.collection('households').doc('h1').collection('progressEvents').doc('t1').get();
      expect(stored.data()!['presentedAt'], isNotNull);
    });
  });
}
