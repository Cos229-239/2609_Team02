import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:famotive/app/app.dart';
import 'package:famotive/core/services/auth_service.dart';
import 'package:famotive/core/services/theme_controller.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeController', () {
    test('defaults to light mode when nothing is saved', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = ThemeController();
      await controller.load();
      expect(controller.mode, ThemeMode.light);
    });

    test('restores a saved dark mode', () async {
      SharedPreferences.setMockInitialValues({ThemeController.prefsKey: 'dark'});
      final controller = ThemeController();
      await controller.load();
      expect(controller.mode, ThemeMode.dark);
    });

    test('ignores an unknown saved value', () async {
      SharedPreferences.setMockInitialValues({ThemeController.prefsKey: 'purple'});
      final controller = ThemeController();
      await controller.load();
      expect(controller.mode, ThemeMode.light);
    });

    test('setDark notifies and persists the choice', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = ThemeController();
      await controller.load();
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.setDark(true);
      expect(controller.mode, ThemeMode.dark);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ThemeController.prefsKey), 'dark');

      await controller.setDark(false);
      expect(controller.mode, ThemeMode.light);
      expect(prefs.getString(ThemeController.prefsKey), 'light');
    });
  });

  testWidgets('FamotiveApp renders in dark mode when the controller says so', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final authService = AuthService(auth: MockFirebaseAuth(), firestore: FakeFirebaseFirestore());
    final controller = ThemeController(initialMode: ThemeMode.dark);

    await tester.pumpWidget(
      FamotiveApp(
        authService: authService,
        navigatorKey: GlobalKey<NavigatorState>(),
        themeController: controller,
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.text('Log In').first);
    expect(Theme.of(context).brightness, Brightness.dark);

    // The mode flips synchronously; the save to disk finishes in the background.
    unawaited(controller.setMode(ThemeMode.light));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('Log In').first)).brightness, Brightness.light);
  });
}
