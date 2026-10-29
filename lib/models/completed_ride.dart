import 'dart:convert';

class CompletedRide {
  const CompletedRide({required this.id, required this.platform, required this.date,
    this.value, this.distanceKm, this.pickup, this.destination,
    this.verified = false, this.conflict = false, this.routeSource = 'unavailable',
    this.revision = 1, this.manuallyReviewed = false});
  final String id, platform, routeSource;
  final DateTime date;
  final double? value, distanceKm;
  final String? pickup, destination;
  final bool verified, conflict, manuallyReviewed;
  final int revision;
  bool get countsInTotals => verified && !conflict && value != null;
  double? get perKm => countsInTotals && distanceKm != null && distanceKm! > 0 ? value! / distanceKm! : null;

  static double? _number(dynamic value, {bool positive = false}) {
    final n = value is num ? value.toDouble() : null;
    return n != null && n.isFinite && (positive ? n > 0 : n >= 0) ? n : null;
  }
  factory CompletedRide.fromJson(Map<String, dynamic> map) => CompletedRide(
    id: map['id'] as String, platform: map['platform'] as String,
    date: map['timestamp'] is num ? DateTime.fromMillisecondsSinceEpoch((map['timestamp'] as num).toInt()) : DateTime.parse(map['date'] as String),
    value: _number(map['value']), distanceKm: _number(map['distanceKm'] ?? map['distance'], positive: true),
    pickup: map['pickup'] as String?, destination: map['destination'] as String?,
    verified: map['verified'] == true, conflict: map['conflict'] == true,
    routeSource: map['routeSource'] as String? ?? 'unavailable',
    revision: (map['revision'] as num?)?.toInt() ?? 1, manuallyReviewed: map['manuallyReviewed'] == true,
  );
  Map<String, dynamic> toJson() => {'id': id, 'platform': platform, 'date': date.toIso8601String(),
    'value': value, 'distanceKm': distanceKm, 'pickup': pickup, 'destination': destination,
    'verified': verified, 'conflict': conflict, 'routeSource': routeSource, 'revision': revision,
    'manuallyReviewed': manuallyReviewed};
}

/// Persists the entire batch before exposing it or acknowledging native delivery.
class CompletedRideRepository {
  CompletedRideRepository({required this.write, List<CompletedRide> initial = const []}) : _rides = List.of(initial);
  final Future<bool> Function(String) write;
  List<CompletedRide> _rides;
  Future<void> _tail = Future.value();
  List<CompletedRide> get rides => List.unmodifiable(_rides);

  Future<void> upsert(List<CompletedRide> incoming) {
    final operation = _tail.then((_) async {
      final byId = {for (final ride in _rides) ride.id: ride};
      for (final ride in incoming) {
        final previous = byId[ride.id];
        if (previous == null || ride.manuallyReviewed || (!previous.manuallyReviewed && ride.revision > previous.revision)) byId[ride.id] = ride;
      }
      final updated = byId.values.toList()..sort((a, b) => b.date.compareTo(a.date));
      if (!await write(jsonEncode(updated.map((r) => r.toJson()).toList()))) throw StateError('Não foi possível salvar as corridas. Tentaremos novamente.');
      _rides = updated;
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }
}
