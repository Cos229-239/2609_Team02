class SteamGame {
  const SteamGame({
    required this.appId,
    required this.name,
    required this.playtimeMinutes,
    this.playtimeLastTwoWeeks,
  });

  final int appId;
  final String name;
  final int playtimeMinutes;
  final int? playtimeLastTwoWeeks;

  factory SteamGame.fromJson(Map<String, dynamic> json) {
    return SteamGame(
      appId: json['appid'] as int,
      name: json['name'] as String,
      playtimeMinutes: json['playtime_forever'] as int? ?? 0,
      playtimeLastTwoWeeks: json['playtime_2weeks'] as int?,
    );
  }
}
