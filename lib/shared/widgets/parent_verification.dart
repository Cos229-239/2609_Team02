import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'parental_gate.dart';

/// "Is a grown-up holding the phone?" for places a child must not get
/// past on a parent's device: leaving Rex's Room in kid mode and opening a
/// child's account settings.
///
/// Tries Face ID / Touch ID / fingerprint first, biometrics only (no
/// device passcode fallback, since kids often know the phone's PIN). If the
/// device has no biometrics enrolled, or the scan fails or is cancelled,
/// the math [ParentalGate] is shown instead, so a parent always has a way
/// through and a child still can't skip it.
///
/// ```dart
/// if (!await ParentVerification.verify(context, reason: 'Open Ava's account')) return;
/// ```
class ParentVerification {
  ParentVerification._();

  /// Swapped in tests.
  @visibleForTesting
  static ParentBiometrics biometrics = LocalParentBiometrics();

  /// [reason] is shown in the Face ID / fingerprint prompt; [gateReason]
  /// on the math question if that's needed instead.
  static Future<bool> verify(
    BuildContext context, {
    required String reason,
    String gateReason = ParentalGate.defaultReason,
  }) async {
    if (await biometrics.isAvailable()) {
      if (await biometrics.authenticate(reason)) return true;
    }
    if (!context.mounted) return false;
    return ParentalGate.verify(context, reason: gateReason);
  }
}

/// The device's biometric check. See [LocalParentBiometrics].
abstract class ParentBiometrics {
  /// True when the device can scan a face/fingerprint and one is enrolled.
  Future<bool> isAvailable();

  /// True only for a successful scan; false for cancel, failure or error.
  Future<bool> authenticate(String reason);
}

class LocalParentBiometrics implements ParentBiometrics {
  LocalParentBiometrics([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      if (!await _auth.isDeviceSupported() || !await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException catch (e) {
      debugPrint('ParentVerification: biometrics unavailable: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, biometricOnly: true);
    } on LocalAuthException catch (e) {
      // Lockout, no hardware, user cancel...: fall back to the math gate.
      debugPrint('ParentVerification: biometric check failed: ${e.code}');
      return false;
    } on PlatformException catch (e) {
      debugPrint('ParentVerification: biometric check failed: $e');
      return false;
    }
  }
}
