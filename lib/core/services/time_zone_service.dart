import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The device's IANA time zone (e.g. "America/Chicago"), read from the
/// native side (ios/Runner/AppDelegate.swift, android/.../MainActivity.kt).
///
/// Households store this so the server can send reminders and roll over
/// repeating tasks at 9 AM *family* time.
class TimeZoneService {
  TimeZoneService._();

  static const MethodChannel _channel = MethodChannel('famotive/timezone');

  /// Null when unavailable (tests, web, an unexpected platform error).
  static Future<String?> localTimeZone() async {
    try {
      final tz = await _channel.invokeMethod<String>('getLocalTimeZone');
      return (tz == null || tz.isEmpty) ? null : tz;
    } on MissingPluginException {
      return null; // tests, or a platform without the native handler
    } catch (e) {
      // PlatformException, or no Flutter binding (plain unit tests).
      debugPrint('TimeZoneService: $e');
      return null;
    }
  }
}
