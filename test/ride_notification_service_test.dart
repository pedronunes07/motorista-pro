import 'package:flutter_test/flutter_test.dart';
import 'package:motorista_pro/services/ride_notification_service.dart';

void main() {
  group('RideOfferParser', () {
    test('extrai corrida da Uber com valores brasileiros', () {
      final offer = RideOfferParser.parse(
        packageName: 'com.ubercab.driver',
        title: 'Nova solicitação de corrida',
        content: r'R$ 24,50 · 8,2 km · 18 min',
      );

      expect(offer, isNotNull);
      expect(offer!.platform, 'Uber');
      expect(offer.fare, 24.50);
      expect(offer.distanceKm, 8.2);
      expect(offer.durationMinutes, 18);
      expect(offer.earningsPerKm, closeTo(2.987, 0.001));
    });

    test('aceita decimal com ponto', () {
      final offer = RideOfferParser.parse(
        packageName: 'com.indriver.driver',
        title: 'Nova viagem',
        content: r'R$ 18.75 · 6.5 km · 12 min',
      );

      expect(offer?.fare, 18.75);
      expect(offer?.distanceKm, 6.5);
    });

    test('ignora notificações que não são ofertas de corrida', () {
      final offer = RideOfferParser.parse(
        packageName: 'com.whatsapp',
        title: 'Mensagem nova',
        content: r'R$ 20,00 em 5 km e 10 min',
      );

      expect(offer, isNull);
    });

    test('ignora oferta incompleta', () {
      final offer = RideOfferParser.parse(
        packageName: 'com.ubercab.driver',
        title: 'Nova corrida',
        content: r'R$ 20,00 · 5 km',
      );

      expect(offer, isNull);
    });
  });
}
