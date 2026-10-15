import 'dart:math' as math;
import 'dart:ui';

/// Where each board space sits: a serpentine ("snake") path that fills rows
/// left→right, then right→left, from the top. Space 0 is Start; space
/// `boardLength` is the finish. Pure, so it's unit tested.
class BoardLayout {
  BoardLayout._(this.centers, this.spaceRadius, this.size, this.columns);

  /// Builds the layout for a board of [boardLength] spaces in [width].
  factory BoardLayout.compute({required int boardLength, required double width, int? columns}) {
    final count = boardLength + 1;
    final cols = columns ?? (width < 360 ? 4 : 5);
    final rows = (count / cols).ceil();
    final cell = width / cols;
    final rowHeight = cell * 0.95;
    final radius = math.min(cell * 0.32, 34.0);
    final centers = <Offset>[];
    for (var i = 0; i < count; i++) {
      final row = i ~/ cols;
      final colInRow = i % cols;
      final col = row.isEven ? colInRow : cols - 1 - colInRow;
      centers.add(Offset(cell * (col + 0.5), rowHeight * (row + 0.5) + radius * 0.4));
    }
    final height = rowHeight * rows + radius * 0.8;
    return BoardLayout._(centers, radius, Size(width, height), cols);
  }

  /// Center of each space, index = space number.
  final List<Offset> centers;
  final double spaceRadius;
  final Size size;
  final int columns;

  int get spaceCount => centers.length;

  /// Point between spaces for a token moving with fractional [position].
  Offset pointAt(double position) {
    if (centers.isEmpty) return Offset.zero;
    final p = position.clamp(0.0, (centers.length - 1).toDouble());
    final i = p.floor();
    if (i >= centers.length - 1) return centers.last;
    final t = p - i;
    return Offset.lerp(centers[i], centers[i + 1], t)!;
  }
}
