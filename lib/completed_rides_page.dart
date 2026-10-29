import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'main.dart' show AppData;
import 'models/completed_ride.dart';

String _money(double value) => NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(value);

class CompletedRidesPage extends StatelessWidget {
  const CompletedRidesPage({super.key, required this.data, required this.onRetry});
  final AppData data;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: data, builder: (context, _) => ListView(
    padding: const EdgeInsets.all(20), children: [
      if (data.rideSyncError != null) Card(child: ListTile(leading: const Icon(Icons.sync_problem),
        title: Text(data.rideSyncError!), trailing: IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh), tooltip: 'Tentar salvar novamente'))),
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Total confirmado das corridas'),
        Text(_money(data.completedRides.where((r) => r.countsInTotals).fold(0, (sum, r) => sum + r.value!)), style: Theme.of(context).textTheme.headlineMedium),
        const Text('Valores pendentes de revisão não entram no total.'),
      ]))),
      if (data.completedRides.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Text('Nenhuma corrida finalizada registrada. Mantenha a leitura ativa até o comprovante aparecer no aplicativo de corrida.')),
      ...data.completedRides.map((ride) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(ride.platform, style: Theme.of(context).textTheme.titleMedium)),
          Text(ride.value == null ? 'Valor não lido' : _money(ride.value!), style: TextStyle(fontWeight: FontWeight.bold, color: ride.countsInTotals ? Colors.green : Colors.orange))]),
        Text(DateFormat('dd/MM/yyyy · HH:mm').format(ride.date)),
        const SizedBox(height: 8),
        if (!ride.verified) const Text('Registro antigo: confira o comprovante. O valor e a distância podem estar incorretos.', style: TextStyle(color: Colors.orange)),
        if (ride.conflict) const Text('Leituras divergentes. Confira o comprovante antes de confirmar.', style: TextStyle(color: Colors.orange)),
        Text(ride.distanceKm == null ? 'Distância realizada: não informada' : 'Distância ${ride.verified ? 'realizada' : 'antiga'}: ${ride.distanceKm!.toStringAsFixed(2).replaceAll('.', ',')} km'),
        Text(ride.perKm == null ? 'R\$/km: aguardando valor e distância confirmados' : '${_money(ride.perKm!)}/km'),
        const Divider(),
        Text('Embarque: ${ride.pickup ?? 'não identificado'}'),
        Text('Desembarque: ${ride.destination ?? 'não identificado'}'),
        if (ride.routeSource == 'accepted_offer') const Text('Endereços da oferta aceita. Podem mudar durante a viagem.', style: TextStyle(fontSize: 12)),
        if (ride.manuallyReviewed) const Text('Conferido por você', style: TextStyle(fontSize: 12)),
        Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _review(context, ride), icon: const Icon(Icons.edit_outlined), label: const Text('Conferir comprovante'))),
      ])))),
    ],
  ));

  Future<void> _review(BuildContext context, CompletedRide ride) async {
    final result = await showDialog<CompletedRide>(context: context, builder: (_) => _ReviewReceipt(ride: ride));
    if (result == null) return;
    try { await data.saveCompletedRides([result]); }
    catch (_) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível gravar. Tente novamente.'))); }
  }
}

class _ReviewReceipt extends StatefulWidget {
  const _ReviewReceipt({required this.ride});
  final CompletedRide ride;
  @override State<_ReviewReceipt> createState() => _ReviewReceiptState();
}

class _ReviewReceiptState extends State<_ReviewReceipt> {
  late final fare = TextEditingController(text: widget.ride.verified ? widget.ride.value?.toStringAsFixed(2) ?? '' : '');
  late final distance = TextEditingController(text: widget.ride.verified ? widget.ride.distanceKm?.toString() ?? '' : '');
  late final pickup = TextEditingController(text: widget.ride.pickup ?? '');
  late final destination = TextEditingController(text: widget.ride.destination ?? '');
  String? error;
  @override void dispose() { for (final c in [fare, distance, pickup, destination]) { c.dispose(); } super.dispose(); }
  double? number(String raw) { final s = raw.trim(); return double.tryParse(s.contains(',') ? s.replaceAll('.', '').replaceAll(',', '.') : s); }
  @override Widget build(BuildContext context) => AlertDialog(title: const Text('Conferir corrida finalizada'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Text('Preencha somente os dados do comprovante final. A distância da oferta pode incluir o deslocamento até o passageiro.'),
    TextField(controller: fare, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Valor recebido (R\$)')),
    TextField(controller: distance, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Distância realizada (km, opcional)')),
    TextField(controller: pickup, decoration: const InputDecoration(labelText: 'Embarque')),
    TextField(controller: destination, decoration: const InputDecoration(labelText: 'Desembarque')),
    if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
  ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: () {
    final value = number(fare.text), km = number(distance.text);
    if (value == null || !value.isFinite || value < 0 || (distance.text.trim().isNotEmpty && (km == null || !km.isFinite || km <= 0))) {
      setState(() => error = 'Confira o valor e a distância digitados.'); return;
    }
    final ride = widget.ride;
    Navigator.pop(context, CompletedRide(id: ride.id, platform: ride.platform, date: ride.date, value: value, distanceKm: km,
      pickup: pickup.text.trim().isEmpty ? null : pickup.text.trim(), destination: destination.text.trim().isEmpty ? null : destination.text.trim(),
      verified: true, manuallyReviewed: true, routeSource: 'manual', revision: ride.revision));
  }, child: const Text('Confirmar dados'))]);
}
