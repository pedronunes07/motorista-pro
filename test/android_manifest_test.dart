import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registra o Motorista Pro no acesso às notificações do Android', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(
      manifest,
      contains('notification.listener.service.NotificationListener'),
    );
    expect(
      manifest,
      contains('android.permission.BIND_NOTIFICATION_LISTENER_SERVICE'),
    );
    expect(
      manifest,
      contains('android.service.notification.NotificationListenerService'),
    );
  });

  test('não solicita câmera nem armazenamento sem necessidade', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(manifest, isNot(contains('android.permission.CAMERA')));
    expect(manifest, isNot(contains('android.permission.READ_EXTERNAL_STORAGE')));
  });
}
