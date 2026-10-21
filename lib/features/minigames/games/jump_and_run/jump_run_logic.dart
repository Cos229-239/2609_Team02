import 'dart:math' as math;

import '../../../../core/models/mini_game.dart';
import '../../../../core/models/mini_game_settings.dart';

/// Something to jump over. Units are meters.
class Obstacle {
  const Obstacle(this.x, this.width, this.height);

  final double x;
  final double width;
  final double height;
}

/// A star to grab, at [x] and center height [y].
class Collectible {
  const Collectible(this.id, this.x, this.y);

  final int id;
  final double x;
  final double y;
}

/// Runner physics. Tuned for kids: a long, high jump with a generous
/// timing window (about half a second for the tallest obstacle).
class JumpPhysics {
  JumpPhysics._();

  static const double speed = JumpAndRunSettings.metersPerSecond * 1.0; // m/s
  static const double gravity = 28; // m/s²
  static const double jumpVelocity = 12; // m/s
  static const double runnerHalfWidth = 0.35;
  static const double runnerHeight = 1.2;

  /// Collisions forgive this much height (the runner "skims" obstacles).
  static const double heightForgiveness = 0.1;

  static double get airTime => 2 * jumpVelocity / gravity;
  static double get apex => jumpVelocity * jumpVelocity / (2 * gravity);

  static const double maxObstacleHeight = 1.0;
  static const double maxObstacleWidth = 1.4;

  /// Shortest start-to-start distance between obstacles: a whole jump, the
  /// obstacle, and room to land and react before the next one.
  static double get minGap => speed * airTime + maxObstacleWidth + 4;
}

/// A procedurally generated course (seeded): obstacles and stars along
/// [runLength] meters. [isCompletable] proves no obstacle is unavoidable.
class JumpRunCourse {
  JumpRunCourse._(this.runLength, this.obstacles, this.collectibles);

  factory JumpRunCourse.generate(JumpAndRunSettings settings, math.Random random) {
    final runLength = settings.runLength.toDouble();
    final (minGap, maxGap) = switch (settings.obstacleDensity) {
      1 => (30.0, 45.0),
      3 => (JumpPhysics.minGap, 24.0),
      _ => (20.0, 34.0),
    };
    final obstacles = <Obstacle>[];
    var x = 25.0 + random.nextDouble() * 5;
    while (x < runLength - 12) {
      obstacles.add(Obstacle(
        x,
        0.8 + random.nextDouble() * (JumpPhysics.maxObstacleWidth - 0.8),
        0.5 + random.nextDouble() * (JumpPhysics.maxObstacleHeight - 0.5),
      ));
      x += minGap + random.nextDouble() * (maxGap - minGap);
    }

    // Exactly settings.collectibleCount stars, spread along the course and
    // kept clear of obstacles. Air stars are within jumping reach.
    final count = settings.collectibleCount;
    final start = 12.0;
    final span = runLength - 8 - start;
    final collectibles = <Collectible>[];
    for (var i = 0; i < count; i++) {
      var sx = start + span * (i + random.nextDouble() * 0.6) / count;
      for (final o in obstacles) {
        if (sx > o.x - 3 && sx < o.x + o.width + 3) sx = o.x + o.width + 3;
      }
      final inAir = random.nextBool();
      collectibles.add(Collectible(i, math.min(sx, runLength - 2), inAir ? 2.0 : 0.6));
    }
    return JumpRunCourse._(runLength, List.unmodifiable(obstacles), List.unmodifiable(collectibles));
  }

  final double runLength;
  final List<Obstacle> obstacles;
  final List<Collectible> collectibles;

  /// Every obstacle can be jumped, there's room to land between them, and
  /// the course is finishable.
  bool get isCompletable {
    for (var i = 0; i < obstacles.length; i++) {
      final o = obstacles[i];
      if (o.height > JumpPhysics.maxObstacleHeight || o.width > JumpPhysics.maxObstacleWidth) return false;
      if (o.x < 20 || o.x + o.width > runLength - 5) return false;
      if (i > 0 && o.x - obstacles[i - 1].x < JumpPhysics.minGap - 1e-9) return false;
    }
    return collectibles.every((c) => c.y <= JumpPhysics.apex + 0.3 && c.x <= runLength);
  }
}

/// The run itself: deterministic stepping, so it's unit tested without a
/// screen. Three hearts; an obstacle hit costs one (with a moment of
/// invulnerability); zero hearts ends the run; reaching the end wins.
class JumpRunSim {
  JumpRunSim(this.course);

  static const int startingHearts = 3;
  static const double invulnerableSeconds = 1.2;

  /// A tap this close before landing still jumps (kids tap early).
  static const double jumpBufferSeconds = 0.15;

  final JumpRunCourse course;

  double x = 0;
  double y = 0;
  double vy = 0;
  double time = 0;
  int hearts = startingHearts;
  int hits = 0;
  double _invulnerableUntil = -1;
  double _jumpRequestedAt = -10;
  final Set<int> collected = {};
  final Set<int> _hitObstacles = {};

  bool get onGround => y <= 0 && vy <= 0;
  bool get isFinished => x >= course.runLength;
  bool get isFailed => hearts <= 0;
  bool get isOver => isFinished || isFailed;
  bool get isInvulnerable => time < _invulnerableUntil;

  /// Obstacles fully passed without a hit.
  int get obstaclesCleared {
    var cleared = 0;
    for (var i = 0; i < course.obstacles.length; i++) {
      final o = course.obstacles[i];
      if (o.x + o.width < x - JumpPhysics.runnerHalfWidth && !_hitObstacles.contains(i)) cleared++;
    }
    return cleared;
  }

  void jump() {
    if (isOver) return;
    if (onGround) {
      vy = JumpPhysics.jumpVelocity;
    } else {
      _jumpRequestedAt = time;
    }
  }

  /// Advances the run by [dt] seconds (callers keep steps small).
  void step(double dt) {
    if (isOver || dt <= 0) return;
    time += dt;
    x = math.min(course.runLength, x + JumpPhysics.speed * dt);
    if (!onGround || vy > 0) {
      vy -= JumpPhysics.gravity * dt;
      y += vy * dt;
      if (y <= 0) {
        y = 0;
        vy = 0;
        if (time - _jumpRequestedAt <= jumpBufferSeconds) {
          vy = JumpPhysics.jumpVelocity;
          _jumpRequestedAt = -10;
        }
      }
    }

    final left = x - JumpPhysics.runnerHalfWidth;
    final right = x + JumpPhysics.runnerHalfWidth;
    for (var i = 0; i < course.obstacles.length; i++) {
      final o = course.obstacles[i];
      if (o.x > right) break;
      final overlapX = right > o.x && left < o.x + o.width;
      if (overlapX && y < o.height - JumpPhysics.heightForgiveness && !isInvulnerable) {
        hearts--;
        hits++;
        _hitObstacles.add(i);
        _invulnerableUntil = time + invulnerableSeconds;
      }
    }
    for (final c in course.collectibles) {
      if (collected.contains(c.id)) continue;
      if ((c.x - x).abs() < 0.8 && c.y + 0.4 > y && c.y - 0.4 < y + JumpPhysics.runnerHeight) {
        collected.add(c.id);
      }
    }
  }

  MiniGameOutcome outcome(Duration elapsed) {
    final distance = x.floor().clamp(0, course.runLength.toInt());
    return MiniGameOutcome(
      gameId: MiniGameId.jumpAndRun,
      details: {
        'distance': distance,
        'runLength': course.runLength.toInt(),
        'collected': collected.length,
        'collectibles': course.collectibles.length,
        'hits': hits,
      },
      performance: MiniGamePerformance.jumpAndRun(
        distance: distance,
        runLength: course.runLength.toInt(),
        collected: collected.length,
        collectibles: course.collectibles.length,
      ),
      elapsed: elapsed,
      completed: isFinished,
    );
  }
}
