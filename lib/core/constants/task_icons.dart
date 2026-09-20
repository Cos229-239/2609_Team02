import 'package:flutter/material.dart';

/// One selectable option in the "choose an icon" grid on the Create Task
/// screen: a stable [key] (what actually gets stored on [TaskModel.icon]
/// and persisted to Firestore), a human label for the picker's tooltip,
/// and the [IconData] to render.
///
/// NOTE: the design called for a Bootstrap Icons grid. This app doesn't
/// have network access available to verify exact `bootstrap_icons`
/// package identifiers against a real build, so this uses Flutter's
/// built-in Material icon set instead — guaranteed to compile and
/// visually similar (outlined, single-color glyphs). Swapping to
/// `BootstrapIcons.xxx` later only means changing the `icon:` value on
/// each [TaskIconEntry] below once the package is added and its exact
/// constant names are confirmed; [key] (what's actually persisted) can
/// stay the same.
class TaskIconEntry {
  const TaskIconEntry(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}

class TaskIconCatalog {
  TaskIconCatalog._();

  static const String defaultKey = 'checklist';

  static const List<TaskIconEntry> all = [
    TaskIconEntry('bed', 'Make Bed', Icons.bed_outlined),
    TaskIconEntry('cleaning', 'Cleaning', Icons.cleaning_services_outlined),
    TaskIconEntry('trash', 'Trash', Icons.delete_outline),
    TaskIconEntry('laundry', 'Laundry', Icons.local_laundry_service_outlined),
    TaskIconEntry('dishes', 'Dishes', Icons.kitchen_outlined),
    TaskIconEntry('table', 'Set Table', Icons.restaurant_outlined),
    TaskIconEntry('homework', 'Homework', Icons.menu_book_outlined),
    TaskIconEntry('reading', 'Reading', Icons.auto_stories_outlined),
    TaskIconEntry('pet', 'Pet Care', Icons.pets_outlined),
    TaskIconEntry('plant', 'Plants', Icons.eco_outlined),
    TaskIconEntry('yard', 'Yard Work', Icons.grass),
    TaskIconEntry('shopping', 'Shopping', Icons.shopping_cart_outlined),
    TaskIconEntry('errand', 'Errands', Icons.directions_car_outlined),
    TaskIconEntry('bike', 'Outdoor', Icons.directions_bike_outlined),
    TaskIconEntry('music', 'Practice', Icons.music_note_outlined),
    TaskIconEntry('art', 'Art', Icons.brush_outlined),
    TaskIconEntry('game', 'Game Time', Icons.sports_esports_outlined),
    TaskIconEntry('gift', 'Bonus', Icons.card_giftcard_outlined),
    TaskIconEntry('star', 'Special', Icons.star_outline),
    TaskIconEntry('outside', 'outdoors', Icons.wb_sunny_outlined),
    TaskIconEntry('food', 'food', Icons.restaurant_outlined),
  ];

  static TaskIconEntry resolve(String key) {
    for (final entry in all) {
      if (entry.key == key) return entry;
    }
    // Falls back gracefully for legacy/seeded data that predates this
    // catalog (e.g. tasks still storing an emoji in `icon`).
    return all.last;
  }
}
