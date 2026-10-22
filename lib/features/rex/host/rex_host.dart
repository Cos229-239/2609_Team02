import 'package:flutter/widgets.dart';

import 'rex_host_native.dart' if (dart.library.js_interop) 'rex_host_web.dart' as impl;

/// Where Rex's Room (the bundled HTML game) runs: a WebView on iOS/Android
/// ([webview_flutter]), an iframe on the web (the QA walkthrough site has
/// no WebView). [RexRoomScreen] only talks to this.
///
/// Messages from the game (`{source: 'rex', type: ...}`) arrive as JSON
/// strings in [onMessage]; [runJavaScript] calls into the page
/// (`RexGame.setTasks(...)` etc.).
abstract class RexHost {
  static RexHost create({
    required void Function(String json) onMessage,
    required bool Function(String url) allowNavigation,
    required Color background,
  }) =>
      impl.createRexHost(onMessage: onMessage, allowNavigation: allowNavigation, background: background);

  Future<void> loadHtml(String html, {required String baseUrl});

  Future<void> runJavaScript(String code);

  Widget build(BuildContext context);

  void dispose();
}
