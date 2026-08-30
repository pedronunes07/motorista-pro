import 'dart:async';

import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

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

    final fareMatch = _money.firstMatch(text);
    final distanceMatch = _distance.firstMatch(text);
    final durationMatch = _duration.firstMatch(text);
    if (fareMatch == null || distanceMatch == null || durationMatch == null) return null;

    final fare = _number(fareMatch.group(1));
    final distance = _number(distanceMatch.group(1));
    final duration = int.tryParse(durationMatch.group(1)!);
    if (fare == null || fare <= 0 || distance == null || distance <= 0 || duration == null || duration <= 0) return null;

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

class RideNotificationService {
  StreamSubscription<ServiceNotificationEvent>? _subscription;
  final _offers = StreamController<RideOffer>.broadcast();

  Stream<RideOffer> get offers => _offers.stream;

  Future<bool> hasPermission() => NotificationListenerService.isPermissionGranted();
  Future<bool> requestPermission() => NotificationListenerService.requestPermission();

  void start() {
    _subscription ??= NotificationListenerService.notificationsStream.listen((event) {
      if (event.hasRemoved == true) return;
      final offer = RideOfferParser.parse(
        packageName: event.packageName,
        title: event.title,
        content: event.content,
      );
      if (offer != null) _offers.add(offer);
    });
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _offers.close();
  }
}
