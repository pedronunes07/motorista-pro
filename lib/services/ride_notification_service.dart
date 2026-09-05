class RideOffer {
  const RideOffer({
    required this.platform,
    required this.fare,
    required this.distanceKm,
    required this.durationMinutes,
    required this.rawText,
  });

  final String platform;
  final double fare;
  final double distanceKm;
  final int durationMinutes;
  final String rawText;

  double get earningsPerKm => distanceKm > 0 ? fare / distanceKm : 0;
  double get earningsPerHour => durationMinutes > 0 ? fare / (durationMinutes / 60) : 0;
  String get id => '$platform:${fare.toStringAsFixed(2)}:${distanceKm.toStringAsFixed(2)}:$durationMinutes';
}
class RideOfferParser {
  static final _money = RegExp(r'R\$\s*([0-9]+(?:[.,][0-9]{1,2})?)', caseSensitive: false);
  static final _distance = RegExp(r'([0-9]+(?:[.,][0-9]+)?)\s*km', caseSensitive: false);
  static final _duration = RegExp(r'([0-9]+)\s*min', caseSensitive: false);

  static RideOffer? parse({String? packageName, String? title, String? content}) {
    final text = '${title ?? ''} ${content ?? ''}'.trim();
    final normalizedPackage = (packageName ?? '').toLowerCase();
    final normalizedText = text.toLowerCase();
    final platform = _platform(normalizedPackage, normalizedText);
    if (platform == null || !_looksLikeOffer(normalizedText)) return null;

    final fares = _money.allMatches(text).map((m) => _number(m.group(1))).whereType<double>().toSet();
    final distances = _distance.allMatches(text).map((m) => _number(m.group(1))).whereType<double>().toSet();
    final durations = _duration.allMatches(text).map((m) => int.tryParse(m.group(1)!)).whereType<int>().toSet();
    if (fares.length != 1 || distances.length != 1 || durations.length != 1) return null;

    final fare = fares.single;
    final distance = distances.single;
    final duration = durations.single;
    if (fare <= 0 || distance <= 0 || duration <= 0) return null;

    return RideOffer(platform: platform, fare: fare, distanceKm: distance, durationMinutes: duration, rawText: text);
  }

  static bool _looksLikeOffer(String text) =>
      text.contains('corrida') || text.contains('viagem') || text.contains('solicitação') || text.contains('chamada');

  static String? _platform(String packageName, String text) {
    if (packageName.contains('uber') || text.contains('uber')) return 'Uber';
    if (packageName.contains('99') || text.contains('99pop') || text.contains('99 ')) return '99';
    if (packageName.contains('indriver') || packageName.contains('indrive') || text.contains('indrive')) return 'inDrive';
    return null;
  }

  static double? _number(String? value) {
    if (value == null) return null;
    final normalized = value.contains(',')
        ? value.replaceAll('.', '').replaceAll(',', '.')
        : value;
    return double.tryParse(normalized);
  }
}
