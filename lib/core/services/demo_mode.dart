import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// Set when the app runs as a demo with sample data (the QA web build at
/// famotive.org/qa/walkthrough, see lib/qa/). Nothing in a demo reaches
/// Firebase: the QA build never initializes it and hands the app in-memory
/// stand-ins instead (see lib/qa/demo_family.dart).
///
/// In a demo, "Log Out" becomes "End test", which calls [onEndTest].
class DemoMode {
  const DemoMode({required this.onEndTest});

  /// Leaves the demo (Settings > End test).
  final VoidCallback onEndTest;

  /// The [DemoMode] provided above [context], or null in the real app (and
  /// in widget tests that pump a single screen without providers).
  static DemoMode? maybeOf(BuildContext context) {
    try {
      return Provider.of<DemoMode?>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }
}
