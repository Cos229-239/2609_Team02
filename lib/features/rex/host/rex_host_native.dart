import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'rex_host.dart';

RexHost createRexHost({
  required void Function(String json) onMessage,
  required bool Function(String url) allowNavigation,
  required Color background,
}) =>
    _WebViewRexHost(onMessage: onMessage, allowNavigation: allowNavigation, background: background);

class _WebViewRexHost implements RexHost {
  _WebViewRexHost({
    required void Function(String json) onMessage,
    required bool Function(String url) allowNavigation,
    required Color background,
  }) : _controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(background)
          // Kids Category (guideline 1.3): the game is a bundled page and
          // must never navigate a child out to the web.
          ..setNavigationDelegate(NavigationDelegate(
            onNavigationRequest: (request) =>
                allowNavigation(request.url) ? NavigationDecision.navigate : NavigationDecision.prevent,
          ))
          ..addJavaScriptChannel('FamotiveBridge', onMessageReceived: (m) => onMessage(m.message));

  final WebViewController _controller;

  @override
  Future<void> loadHtml(String html, {required String baseUrl}) => _controller.loadHtmlString(html, baseUrl: baseUrl);

  @override
  Future<void> runJavaScript(String code) => _controller.runJavaScript(code);

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);

  @override
  void dispose() {}
}
