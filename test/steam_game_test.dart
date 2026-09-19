import 'package:flutter_test/flutter_test.dart';
import 'package:famotive/core/models/steam_game.dart';

void main() {
  test('creates SteamGame from JSON', () {
    final json = {
      'appid': 12345,
      'name': 'Test Game',
      'playtime_forever': 600,
      'playtime_2weeks': 120,
    };

    final game = SteamGame.fromJson(json);

    expect(game.appId, 12345);
    expect(game.name, 'Test Game');
    expect(game.playtimeMinutes, 600);
    expect(game.playtimeLastTwoWeeks, 120);
  });

  test('handles missing two-week playtime', () {
    final json = {'appid': 12345, 'name': 'Test Game', 'playtime_forever': 600};

    final game = SteamGame.fromJson(json);

    expect(game.appId, 12345);
    expect(game.name, 'Test Game');
    expect(game.playtimeMinutes, 600);
    expect(game.playtimeLastTwoWeeks, isNull);
  });
}
