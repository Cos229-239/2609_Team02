import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';

/// Terms & Privacy live on famotive.org, so the app always shows the current
/// version. They open in an in-app browser (Safari View Controller / Chrome
/// Custom Tab) over the app.
class LegalLinks {
  LegalLinks._();

  static Future<void> openTerms(BuildContext context) => _open(context, AppConstants.termsUrl);
  static Future<void> openPrivacy(BuildContext context) => _open(context, AppConstants.privacyUrl);

  static Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
    } catch (e) {
      debugPrint('LegalLinks: could not open $url: $e');
    }
    if (!opened) {
      messenger?.showSnackBar(SnackBar(content: Text("Couldn't open the page. Visit $url")));
    }
  }
}

/// "By continuing, you agree to our Terms & Conditions and Privacy Policy."
/// Shown under the sign-in / sign-up buttons.
class LegalFooter extends StatelessWidget {
  const LegalFooter({super.key, this.prefix = 'By continuing, you agree to our'});

  final String prefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600);
    final link = style?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600);

    Widget linkText(String label, Future<void> Function(BuildContext) open) => InkWell(
          onTap: () => open(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(label, style: link),
          ),
        );

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('$prefix ', style: style),
        linkText('Terms & Conditions', LegalLinks.openTerms),
        Text(' and ', style: style),
        linkText('Privacy Policy', LegalLinks.openPrivacy),
        Text('.', style: style),
      ],
    );
  }
}
