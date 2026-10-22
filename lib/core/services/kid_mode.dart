import 'package:flutter/foundation.dart';

/// Whether a parent has handed this device to a child (Rex's Room in kid
/// mode, see RexRoomScreen). While it's on, nothing may take the child out
/// of Rex without the parental gate: e.g. [NotificationService] holds back
/// the parent's in-app notification banners and notification taps.
class KidMode {
  KidMode._();

  static final ValueNotifier<bool> active = ValueNotifier(false);

  static bool get isActive => active.value;
}
