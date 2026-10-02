package com.famotive

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Device time zone (IANA id, e.g. "America/Chicago") for the household's
        // 9 AM reminders. Read by lib/core/services/time_zone_service.dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "famotive/timezone")
            .setMethodCallHandler { call, result ->
                if (call.method == "getLocalTimeZone") {
                    result.success(TimeZone.getDefault().id)
                } else {
                    result.notImplemented()
                }
            }
    }
}
