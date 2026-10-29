import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:motorista_pro/models/completed_ride.dart';

Map<String,dynamic> record({String id = 'trip-1', int revision = 1, double? value = 26.25, double? distance, bool verified = true}) => {
  'id': id, 'platform': '99', 'timestamp': 1000, 'value': value, 'distance': distance, 'verified': verified, 'revision': revision,
  'pickup': 'Rua A, 1, Recife - PE', 'destination': 'Rua B, 2, Recife - PE', 'routeSource': 'receipt',
};

void main() {
  test('unknown kilometers remain unknown and never calculate an invented rate', () {
    final ride = CompletedRide.fromJson(record());
    expect(ride.value, 26.25); expect(ride.distanceKm, isNull); expect(ride.perKm, isNull);
  });
  test('actual values calculate the real price per kilometer', () {
    final ride = CompletedRide.fromJson(record(distance: 3.5));
    expect(ride.perKm, 7.5);
    expect(CompletedRide.fromJson(ride.toJson()).destination, 'Rua B, 2, Recife - PE');
  });
  test('unverified legacy data is preserved but excluded from totals', () {
    final map = record(distance: 12)..remove('verified');
    final ride = CompletedRide.fromJson(map);
    expect(ride.value, 26.25); expect(ride.countsInTotals, isFalse); expect(ride.perKm, isNull);
  });
  test('invalid numeric fields do not enter financial calculations', () {
    for (final value in [double.nan, double.infinity, -1.0]) {
      final ride = CompletedRide.fromJson(record(value: value, distance: value));
      expect(ride.value, isNull); expect(ride.distanceKm, isNull); expect(ride.countsInTotals, isFalse);
    }
    expect(CompletedRide.fromJson(record(value: 0)).countsInTotals, isTrue);
  });
  test('conflicting readings do not enter totals', () {
    final ride = CompletedRide.fromJson(record()..['conflict'] = true);
    expect(ride.countsInTotals, isFalse);
  });
  test('failed storage never updates memory and can be retried', () async {
    var succeeds = false;
    final repo = CompletedRideRepository(write: (_) async => succeeds);
    final ride = CompletedRide.fromJson(record());
    await expectLater(repo.upsert([ride]), throwsStateError);
    expect(repo.rides, isEmpty);
    succeeds = true; await repo.upsert([ride]);
    expect(repo.rides.single.id, ride.id);
  });
  test('redelivery is idempotent, new revisions enrich the same receipt', () async {
    String? snapshot;
    final repo = CompletedRideRepository(write: (s) async { snapshot = s; return true; });
    final ride = CompletedRide.fromJson(record());
    await repo.upsert([ride]); await repo.upsert([ride]);
    await repo.upsert([CompletedRide.fromJson(record(revision: 2, distance: 3.5))]);
    await repo.upsert([ride]);
    expect(repo.rides.length, 1); expect(repo.rides.single.perKm, 7.5);
    final restarted = CompletedRideRepository(write: (_) async => true,
      initial: (jsonDecode(snapshot!) as List).map((r) => CompletedRide.fromJson(Map<String,dynamic>.from(r as Map))).toList());
    expect(restarted.rides.single.pickup, ride.pickup);
    await restarted.upsert([ride]); expect(restarted.rides.length, 1);
  });
  test('concurrent import batches are serialized without losing rides', () async {
    final repo = CompletedRideRepository(write: (_) async { await Future<void>.delayed(const Duration(milliseconds: 2)); return true; });
    await Future.wait([repo.upsert([CompletedRide.fromJson(record())]), repo.upsert([CompletedRide.fromJson(record(id: 'trip-2'))])]);
    expect(repo.rides.length, 2);
  });
  test('later OCR cannot overwrite a manual correction', () async {
    final repo = CompletedRideRepository(write: (_) async => true);
    await repo.upsert([CompletedRide.fromJson(record(value: 28)..['manuallyReviewed'] = true)]);
    await repo.upsert([CompletedRide.fromJson(record(value: 280, revision: 3))]);
    expect(repo.rides.single.value, 28);
  });
}
