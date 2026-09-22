class DescriptionSuggester {
  DescriptionSuggester._();

  /// Keyed by [TaskIconCatalog] icon key.
  static const Map<String, String> _byIcon = {
    "bed": "Make the bed neatly - straighten the sheets, fluff the pillows and tuck in the corners.",
    "cleaning": "Tidy and wipe down the room: put things away, dust surfaces and vacuum or sweep the floor.",
    "trash": "Collect the trash from around the house, tie off the bags and take them out to the bin.",
    "laundry": "Sort, wash, dry and put away a load of laundry.",
    "dishes": "Load or wash the dishes, then dry and put them away.",
    "table": "Set the table with plates, cups and silverware before the meal.",
    "homework": "Finish today's homework and double-check it before putting it away.",
    "reading": "Read for the assigned amount of time, then be ready to share what happened in the story.",
    "pet": "Feed the pet, refill their water and check that their space is clean.",
    "plant": "Water the plants and check the soil, leaves and pots for anything that needs attention.",
    "yard": "Help out in the yard - mowing, raking, weeding or watering, as needed.",
    "shopping": "Help with the shopping - make the list, find the items or help carry bags in.",
    "errand": "Run the errand and check back in once it's done.",
    "bike": "Get outside for some active time - biking, walking or playing.",
    "music": "Practice for the scheduled amount of time and warm up first.",
    "art": "Work on the art project and clean up the supplies when finished.",
    "game": "Enjoy some earned game time, then wrap up when the time is up.",
    "gift": "Complete this bonus task for some extra recognition.",
    "star": "Complete this special task - ask a parent if anything is unclear.",
    "outside": "Spend some time outside getting fresh air and moving around.",
    "food": "Help prepare or clean up a meal or snack.",
  };

  /// Suggests a description for [title], falling back to a generic one.
  static String suggest({required String title, String? iconKey}) {
    final trimmedTitle = title.trim();

    final byIcon = iconKey == null ? null : _byIcon[iconKey];
    if (byIcon != null) return byIcon;

    final lowerTitle = trimmedTitle.toLowerCase();
    for (final entry in _byIcon.entries) {
      if (lowerTitle.contains(entry.key)) return entry.value;
    }

    if (trimmedTitle.isEmpty) {
      return "Describe what needs to happen for this task to count as done.";
    }
    return "Complete \"$trimmedTitle\" and let a parent know when it's done - nice work!";
  }
}
