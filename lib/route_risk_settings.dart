import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RouteRiskSettings extends StatefulWidget {
  const RouteRiskSettings({super.key});
  @override State<RouteRiskSettings> createState() => _RouteRiskSettingsState();
}
class _RouteRiskSettingsState extends State<RouteRiskSettings> {
  static const channel = MethodChannel('motorista_pro/overlay');
  bool configured = false, enabled = false;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final state = await channel.invokeMapMethod<String,dynamic>('getRiskSettings');
      if (mounted) setState(() { configured = state?['configured'] == true; enabled = state?['enabled'] == true; });
    } on PlatformException catch (_) { /* Unavailable platforms keep the switch disabled. */ }
    on MissingPluginException catch (_) { /* Desktop preview. */ }
  }
  @override Widget build(BuildContext context) => Card(child: Column(children: [
    SwitchListTile(title: const Text('Alertas no embarque e desembarque'),
      subtitle: Text(configured ? 'Consultar áreas de atenção com fonte e data' : 'Indisponível: ainda falta conectar uma fonte confiável de áreas de risco.'),
      value: enabled, onChanged: configured ? _toggle : null),
    const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('A cobertura depende da fonte de cada cidade. Sem informação, aparecerá “sem dados”. Isso não significa que o local seja seguro.')),
  ]));
  Future<void> _toggle(bool value) async {
    if (value) {
      final allowed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Consultar endereços da oferta?'),
        content: const Text('Os endereços de embarque e desembarque serão enviados ao serviço de consulta para verificar alertas. Nenhum nome de passageiro ou valor da corrida será enviado. A IA só auxilia a consulta; não determina risco sem fonte.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context,false), child: const Text('Agora não')), FilledButton(onPressed: () => Navigator.pop(context,true), child: const Text('Ativar consultas'))]));
      if (allowed != true || !mounted) return;
    }
    try {
      final result = await channel.invokeMethod<bool>('setRiskEnabled',value);
      if (mounted) setState(() => enabled = result == true);
    } on PlatformException catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível alterar os alertas. Tente novamente.')));
    }
  }
}
