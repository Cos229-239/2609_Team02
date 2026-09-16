import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/services/auth_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final authService = AuthService();
  await authService.tryRestoreSession();

  runApp(FamotiveApp(authService: authService));
}
