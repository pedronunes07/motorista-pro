import 'dart:async';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

class RideOffer { const RideOffer({required this.platform,required this.fare,required this.distanceKm,required this.durationMinutes,required this.rawText}); final String platform,rawText; final double fare,distanceKm; final int durationMinutes; double get earningsPerKm=>fare/distanceKm; double get earningsPerHour=>fare*60/durationMinutes; }
class RideOfferParser {
 static final money=RegExp(r'R\$\s*((?:[0-9]{1,3}(?:\.[0-9]{3})+,[0-9]{2}|[0-9]+[,.][0-9]{2}|[0-9]+))(?![0-9.,])'),km=RegExp(r'([0-9]+(?:[.,][0-9]+)?)\s*km',caseSensitive:false),min=RegExp(r'([0-9]+)\s*min',caseSensitive:false);
 static double? number(String? v) {
   if (v == null) return null;
   final normalized = v.contains(',')
       ? v.replaceAll('.', '').replaceAll(',', '.')
       : v;
   return double.tryParse(normalized);
 }
 static RideOffer? parse({String? packageName,String? title,String? content}){final text='${title??''} ${content??''}',p=(packageName??'').toLowerCase(),lower=text.toLowerCase();final platform=p.contains('uber')?'Uber':p.contains('99')?'99':(p.contains('indrive')?'inDrive':null);if(platform==null||!['corrida','viagem','solicitação','chamada'].any(lower.contains))return null;if(['finalizada','concluída','concluida','cancelada','resumo','saldo','ganhos da semana'].any(lower.contains))return null;final fs=money.allMatches(text).map((m)=>number(m.group(1))).whereType<double>().toSet(),ds=km.allMatches(text).map((m)=>number(m.group(1))).whereType<double>().toSet(),ts=min.allMatches(text).map((m)=>int.tryParse(m.group(1)!)).whereType<int>().toSet();if(fs.length!=1||ds.length!=1||ts.length!=1||!fs.single.isFinite||fs.single<=0||!ds.single.isFinite||ds.single<=0||ts.single<=0)return null;return RideOffer(platform:platform,fare:fs.single,distanceKm:ds.single,durationMinutes:ts.single,rawText:text);}
}
class RideNotificationService { StreamSubscription<ServiceNotificationEvent>? sub; final controller=StreamController<RideOffer>.broadcast(); Stream<RideOffer> get offers=>controller.stream; Future<bool> hasPermission()=>NotificationListenerService.isPermissionGranted(); Future<bool> requestPermission()=>NotificationListenerService.requestPermission(); void start(){sub??=NotificationListenerService.notificationsStream.listen((e){if(e.hasRemoved==true)return;final o=RideOfferParser.parse(packageName:e.packageName,title:e.title,content:e.content);if(o!=null)controller.add(o);});} Future<void> dispose()async{await sub?.cancel();await controller.close();} }
