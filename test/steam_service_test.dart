import 'package:flutter_test/flutter_test.dart';
import 'package:famotive/core/services/steam_service.dart';

void main() {
  group('SteamService', () {
    final service = SteamService();

    test('parses owned games from Steam response', () {
      final json = {
        'response': {
          'game_count': 2,
          'games': [
            {
              'appid': 12345,
              'name': 'Test Game One',
              'playtime_forever': 600,
              'playtime_2weeks': 120,
            },
            {'appid': 67890, 'name': 'Test Game Two', 'playtime_forever': 300},
          ],
        },
      };

      final games = service.parseOwnedGames(json);

      expect(games.length, 2);

      expect(games[0].appId, 12345);
      expect(games[0].name, 'Test Game One');
      expect(games[0].playtimeMinutes, 600);
      expect(games[0].playtimeLastTwoWeeks, 120);

      expect(games[1].appId, 67890);
      expect(games[1].name, 'Test Game Two');
      expect(games[1].playtimeMinutes, 300);
      expect(games[1].playtimeLastTwoWeeks, isNull);
    });

    test('returns empty list when games are missing', () {
      final json = {
        'response': {'game_count': 0},
      };

      final games = service.parseOwnedGames(json);

      expect(games, isEmpty);
    });

    test('returns empty list when response is missing', () {
      final json = <String, dynamic>{};

      final games = service.parseOwnedGames(json);

      expect(games, isEmpty);
    });
  });
}
