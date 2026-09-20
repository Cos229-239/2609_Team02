import '../models/steam_game.dart';

class SteamService {
  List<SteamGame> parseOwnedGames(Map<String, dynamic> json) {
    final response = json['response'] as Map<String, dynamic>?;
    final games = response?['games'] as List<dynamic>?;

    if (games == null) {
      return [];
    }

    return games
        .map((game) => SteamGame.fromJson(game as Map<String, dynamic>))
        .toList();
  }
}
