# Motorista Pro

Aplicativo Flutter para motoristas de Uber, 99, inDrive e outros aplicativos.

O repositório também inclui uma versão web responsiva em `index.html`, pronta
para publicação na Vercel. Os dados são mantidos localmente no navegador ou no
dispositivo; nenhuma chave de serviço é exposta no cliente.

## Executar

1. Instale o Flutter SDK e adicione-o ao PATH.
2. Na pasta do projeto, execute `flutter pub get`.
3. Execute `flutter run` em um emulador, dispositivo Android ou simulador iOS.

## Próximas integrações

- Firebase Authentication e Cloud Firestore para contas e sincronização.
- Firebase Cloud Messaging para lembretes de manutenção e documentos.
- Uma API segura no backend para IA, sem expor a chave da OpenAI no aplicativo.
- Google Maps/Mapbox para áreas de demanda e pontos úteis.

## Funcionalidades atuais

- Controle de receitas, despesas, metas e saldo líquido.
- Registro de abastecimentos e quilometragem.
- Agenda de manutenção e documentos com persistência local.
- Relatório financeiro e exportação CSV na versão web.
- Assistente local com respostas baseadas nos dados registrados.

## Detecção automática de corridas (Android)

O aplicativo pode ler notificações de ofertas da Uber, 99 e inDrive, extrair
valor, distância e duração e mostrar automaticamente o ganho por km e por hora.
O motorista precisa tocar no ícone de radar e autorizar o acesso às notificações
nas configurações do Android. A oferta só é registrada após confirmação.

A integração usa `notification_listener_service`. Depois de gerar a plataforma
Android com `flutter create . --platforms=android`, adicione dentro de
`<application>` no `android/app/src/main/AndroidManifest.xml`:

```xml
<service
    android:name="notification.listener.service.NotificationListener"
    android:label="Leitura de corridas"
    android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"
    android:exported="true">
    <intent-filter>
        <action android:name="android.service.notification.NotificationListenerService" />
    </intent-filter>
</service>
```

A detecção depende do texto exibido por cada plataforma. Ofertas sem preço,
distância ou duração na notificação não são calculadas automaticamente.
