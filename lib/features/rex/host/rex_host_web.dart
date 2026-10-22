import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'rex_host.dart';

RexHost createRexHost({
  required void Function(String json) onMessage,
  required bool Function(String url) allowNavigation,
  required Color background,
}) =>
    _IframeRexHost(onMessage: onMessage, background: background);

@JS('JSON.stringify')
external JSString? _stringify(JSAny? value);

/// Web: the game in a same-origin iframe (a blob: URL of the bundled page).
/// The game posts to `window.parent` when it isn't in a WebView, and we call
/// `RexGame` on the iframe's window directly. The sandbox keeps it from
/// navigating the page or opening pop-ups.
class _IframeRexHost implements RexHost {
  _IframeRexHost({required this.onMessage, required Color background}) {
    _frame = web.HTMLIFrameElement()
      ..setAttribute('sandbox', 'allow-scripts allow-same-origin')
      ..setAttribute('allow', 'autoplay')
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = '#${(background.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _frame);
    _listener = _onWindowMessage.toJS;
    web.window.addEventListener('message', _listener);
  }

  static int _count = 0;

  final void Function(String json) onMessage;
  final String _viewType = 'famotive-rex-${_count++}';
  late final web.HTMLIFrameElement _frame;
  late final JSFunction _listener;
  String? _blobUrl;

  void _onWindowMessage(web.MessageEvent event) {
    final json = _stringify(event.data)?.toDart;
    // Only the game's own messages ({source: 'rex', ...}).
    if (json == null || !json.contains('"source":"rex"')) return;
    onMessage(json);
  }

  @override
  Future<void> loadHtml(String html, {required String baseUrl}) async {
    final blob = web.Blob(<JSAny>[html.toJS].toJS, web.BlobPropertyBag(type: 'text/html'));
    final old = _blobUrl;
    _blobUrl = web.URL.createObjectURL(blob);
    _frame.src = _blobUrl!;
    if (old != null) web.URL.revokeObjectURL(old);
  }

  @override
  Future<void> runJavaScript(String code) async {
    final win = _frame.contentWindow;
    if (win == null) return;
    try {
      (win as JSObject).callMethod<JSAny?>('eval'.toJS, code.toJS);
    } catch (e) {
      debugPrint('RexHost (web): script failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    final url = _blobUrl;
    if (url != null) web.URL.revokeObjectURL(url);
  }
}
