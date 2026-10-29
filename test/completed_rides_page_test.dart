import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:motorista_pro/main.dart';
import 'package:motorista_pro/completed_rides_page.dart';

void main() {
  testWidgets('history shows addresses, actual rate and only confirmed totals', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final data = AppData(); await data.load();
    await data.saveCompletedRides([CompletedRide(id:'1',platform:'99',date:DateTime(2026,10,28),value:26.25,distanceKm:3.5,
      verified:true,pickup:'Rua A, 100',destination:'Rua B, 200',routeSource:'receipt')]);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:CompletedRidesPage(data:data,onRetry:() async {}))));
    expect(find.text('Embarque: Rua A, 100'),findsOneWidget);
    expect(find.text('Desembarque: Rua B, 200'),findsOneWidget);
    expect(find.textContaining('7,50/km'),findsOneWidget);
    expect(data.income,26.25); expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox()); data.dispose();
  });
  test('migration preserves old history without duplicating its automatic income', () async {
    SharedPreferences.setMockInitialValues({
      'completedRides': jsonEncode([{'id':'old','platform':'99','value':999.0,'distanceKm':1.0,'date':'2026-10-28T00:00:00.000'}]),
      'entries': jsonEncode([{'title':'99 · corrida finalizada','category':'Corridas','value':999.0,'income':true,'date':'2026-10-28T00:00:00.000'},
        {'title':'Receita manual','category':'Ganhos','value':10.0,'income':true,'date':'2026-10-28T00:00:00.000'}]),
    });
    final data=AppData(); await data.load();
    expect(data.completedRides.single.value,999.0); expect(data.income,10.0);
    await data.saveCompletedRides([CompletedRide(id:'old',platform:'99',date:DateTime(2026,10,28),value:26.25,distanceKm:3.5,verified:true,manuallyReviewed:true)]);
    expect(data.income,36.25); expect(data.entries.length,2); data.dispose();
  });
}
