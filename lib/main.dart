import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/ride_notification_service.dart';

void main() => runApp(const MotoristaProApp());

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: RideOverlayView()));
}

Future<void> _shareOverlayReliably(Map<String, dynamic> data) async {
  final payload = jsonEncode(data);
  for (final delay in const [700, 1200, 1800]) {
    await Future<void>.delayed(Duration(milliseconds: delay));
    await FlutterOverlayWindow.shareData(payload);
  }
}

const _nativeOverlay = MethodChannel('motorista_pro/overlay');

Future<void> _showNativeRideOverlay(Map<String, dynamic> data) async {
  await _nativeOverlay.invokeMethod<void>('showRideOverlay', data);
}

class MotoristaProApp extends StatelessWidget {
  const MotoristaProApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Motorista Pro',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF155EEF),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF7F8FC),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF7EA6FF),
            brightness: Brightness.dark,
          ),
        ),
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      );
}

class TransactionEntry {
  const TransactionEntry({
    required this.title,
    required this.category,
    required this.value,
    required this.isIncome,
    required this.date,
  });
  final String title;
  final String category;
  final double value;
  final bool isIncome;
  final DateTime date;
}

class AppData extends ChangeNotifier {
  final List<TransactionEntry> entries = [];
  double dailyGoal = 350;
  double weeklyGoal = 2100;
  double monthlyGoal = 8500;
  double odometer = 0;
  double fuelLiters = 0;
  double fuelCost = 0;
  final List<String> reminders = [];
  double calculatorYellowPerKm = 1.50;
  double calculatorGreenPerKm = 2.00;

  double get income => entries.where((e) => e.isIncome).fold(0, (sum, e) => sum + e.value);
  double get expense => entries.where((e) => !e.isIncome).fold(0, (sum, e) => sum + e.value);
  double get balance => income - expense;
  double get goalProgress => dailyGoal > 0 ? (income / dailyGoal).clamp(0, 1) : 0;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    dailyGoal = prefs.getDouble('dailyGoal') ?? dailyGoal;
    weeklyGoal = prefs.getDouble('weeklyGoal') ?? weeklyGoal;
    monthlyGoal = prefs.getDouble('monthlyGoal') ?? monthlyGoal;
    odometer = prefs.getDouble('odometer') ?? odometer;
    fuelLiters = prefs.getDouble('fuelLiters') ?? fuelLiters;
    fuelCost = prefs.getDouble('fuelCost') ?? fuelCost;
    calculatorYellowPerKm = prefs.getDouble('calculatorYellowPerKm') ?? calculatorYellowPerKm;
    calculatorGreenPerKm = prefs.getDouble('calculatorGreenPerKm') ?? calculatorGreenPerKm;
    reminders
      ..clear()
      ..addAll(prefs.getStringList('reminders') ?? ['Troca de óleo em 1.250 km', 'Licenciamento em dezembro']);
    final rawEntries = prefs.getString('entries');
    if (rawEntries != null) {
      final saved = jsonDecode(rawEntries) as List<dynamic>;
      entries
        ..clear()
        ..addAll(saved.map((item) {
          final map = item as Map<String, dynamic>;
          return TransactionEntry(title: map['title'] as String, category: map['category'] as String, value: (map['value'] as num).toDouble(), isIncome: map['income'] as bool, date: DateTime.parse(map['date'] as String));
        }));
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('dailyGoal', dailyGoal);
    await prefs.setDouble('weeklyGoal', weeklyGoal);
    await prefs.setDouble('monthlyGoal', monthlyGoal);
    await prefs.setDouble('odometer', odometer);
    await prefs.setDouble('fuelLiters', fuelLiters);
    await prefs.setDouble('fuelCost', fuelCost);
    await prefs.setDouble('calculatorYellowPerKm', calculatorYellowPerKm);
    await prefs.setDouble('calculatorGreenPerKm', calculatorGreenPerKm);
    await prefs.setStringList('reminders', reminders);
    await prefs.setString('entries', jsonEncode(entries.map((e) => {'title': e.title, 'category': e.category, 'value': e.value, 'income': e.isIncome, 'date': e.date.toIso8601String()}).toList()));
  }

  void add(TransactionEntry entry) {
    entries.insert(0, entry);
    _save();
    notifyListeners();
  }

  void updateGoals({required double daily, required double weekly, required double monthly}) {
    dailyGoal = daily;
    weeklyGoal = weekly;
    monthlyGoal = monthly;
    _save();
    notifyListeners();
  }

  void updateCalculator({required double yellowPerKm, required double greenPerKm}) {
    calculatorYellowPerKm = yellowPerKm;
    calculatorGreenPerKm = greenPerKm;
    _save();
    notifyListeners();
  }

  void addReminder(String reminder) {
    final normalized = reminder.trim();
    if (normalized.isEmpty) return;
    reminders.add(normalized);
    _save();
    notifyListeners();
  }

  void removeReminder(String reminder) {
    reminders.remove(reminder);
    _save();
    notifyListeners();
  }

  void addFuel({required double liters, required double cost, required double kilometers}) {
    fuelLiters = liters;
    fuelCost = cost;
    odometer = kilometers;
    add(TransactionEntry(title: 'Abastecimento', category: 'Combustível', value: cost, isIncome: false, date: DateTime.now()));
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final data = AppData();
  final rideNotifications = RideNotificationService();
  StreamSubscription<RideOffer>? rideSubscription;
  int index = 0;
  late final List<Widget> pages;

  @override
  void initState() {
    super.initState();
    data.load();
    if (_supportsRideDetection) {
      rideNotifications.start();
      rideSubscription = rideNotifications.offers.listen(_showRideOffer);
    }
    pages = [Dashboard(data: data), TransactionsPage(data: data), GoalsPage(data: data), VehiclePage(data: data), AssistantPage(data: data)];
  }

  bool get _supportsRideDetection => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _showRideOffer(RideOffer offer) async {
    if (!mounted) return;
    await _showRideOverlay(offer);
    final shouldRegister = await showDialog<bool>(
      context: context,
      builder: (_) => RideOfferDialog(offer: offer),
    );
    if (shouldRegister == true) {
      data.add(TransactionEntry(
        title: '${offer.platform} · ${offer.distanceKm.toStringAsFixed(1)} km',
        category: 'Ganhos',
        value: offer.fare,
        isIncome: true,
        date: DateTime.now(),
      ));
    }
  }

  Future<void> _showRideOverlay(RideOffer offer) async {
    if (!_supportsRideDetection || !await FlutterOverlayWindow.isPermissionGranted()) return;
    await _showNativeRideOverlay({
      'platform': offer.platform,
      'fare': offer.fare,
      'distance': offer.distanceKm,
      'minutes': offer.durationMinutes,
      'perKm': offer.earningsPerKm,
      'perHour': offer.earningsPerHour,
      'yellow': data.calculatorYellowPerKm,
      'green': data.calculatorGreenPerKm,
    });
  }

  Future<void> _requestRideAccess() async {
    final granted = await rideNotifications.requestPermission();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(granted
          ? 'Leitura de corridas ativada.'
          : 'Ative o acesso às notificações para calcular corridas automaticamente.'),
    ));
  }

  Future<void> _openCalculatorSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CalculatorSettingsPage(data: data, notifications: rideNotifications)));
  }

  @override
  void dispose() {
    rideSubscription?.cancel();
    rideNotifications.dispose();
    data.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    const titles = ['Visão geral', 'Movimentações', 'Metas', 'Veículo', 'Assistente IA'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[index], style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(onPressed: _openCalculatorSettings, icon: const Icon(Icons.tune), tooltip: 'Configurar calculadora flutuante'),
          IconButton(onPressed: _requestRideAccess, icon: const Icon(Icons.radar), tooltip: 'Ativar leitura de corridas'),
          IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportsPage(data: data))), icon: const Icon(Icons.bar_chart_outlined), tooltip: 'Relatórios'),
          IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RemindersPage(data: data))), icon: const Icon(Icons.notifications_none_outlined), tooltip: 'Lembretes'),
        ],
      ),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Lançamentos'),
          NavigationDestination(icon: Icon(Icons.flag_outlined), selectedIcon: Icon(Icons.flag), label: 'Metas'),
          NavigationDestination(icon: Icon(Icons.directions_car_outlined), selectedIcon: Icon(Icons.directions_car), label: 'Veículo'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'IA'),
        ],
      ),
    );
  }
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key, required this.data});
  final AppData data;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: data,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Olá, Pedro 👋', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Seu resumo de hoje', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54)),
            const SizedBox(height: 20),
            _BalanceCard(value: data.balance),
            const SizedBox(height: 16),
            Row(children: [Expanded(child: _MetricCard(label: 'Ganhos', value: data.income, icon: Icons.trending_up, color: Colors.green)), const SizedBox(width: 12), Expanded(child: _MetricCard(label: 'Gastos', value: data.expense, icon: Icons.trending_down, color: Colors.red))]),
            const SizedBox(height: 20),
            _GoalCard(progress: data.goalProgress, current: data.income, goal: data.dailyGoal),
            const SizedBox(height: 24),
            Text('Lançamentos recentes', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...data.entries.take(4).map((entry) => _EntryTile(entry: entry)),
          ],
        ),
      );
}

class TransactionsPage extends StatelessWidget {
  const TransactionsPage({super.key, required this.data});
  final AppData data;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: data,
        builder: (context, _) => Scaffold(
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: data.entries.map((e) => _EntryTile(entry: e)).toList()),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => AddEntrySheet(data: data)),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar'),
          ),
        ),
      );
}

class AddEntrySheet extends StatefulWidget {
  const AddEntrySheet({super.key, required this.data});
  final AppData data;
  @override
  State<AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends State<AddEntrySheet> {
  final name = TextEditingController();
  final value = TextEditingController();
  bool income = true;
  @override
  void dispose() { name.dispose(); value.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Novo lançamento', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(income ? 'Receita' : 'Despesa'), value: income, onChanged: (v) => setState(() => income = v)),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Descrição', hintText: 'Ex.: Uber ou Combustível')),
          TextField(controller: value, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Valor (R\$)')),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () { final amount = double.tryParse(value.text.replaceAll(',', '.')); if (name.text.trim().isNotEmpty && amount != null && amount > 0) { widget.data.add(TransactionEntry(title: name.text.trim(), category: income ? 'Ganhos' : 'Despesa', value: amount, isIncome: income, date: DateTime.now())); Navigator.pop(context); } }, child: const Text('Salvar lançamento'))),
        ]),
      );
}

class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key, required this.data});
  final AppData data;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: data, builder: (context, _) => ListView(padding: const EdgeInsets.all(20), children: [
    Text('Planeje seus ganhos', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
    const SizedBox(height: 16),
    _InfoCard(icon: Icons.today_outlined, title: 'Meta diária', subtitle: '${_currency(data.dailyGoal)} · acompanhe no painel'),
    _InfoCard(icon: Icons.calendar_view_week_outlined, title: 'Meta semanal', subtitle: _currency(data.weeklyGoal)),
    _InfoCard(icon: Icons.calendar_month_outlined, title: 'Meta mensal', subtitle: _currency(data.monthlyGoal)),
    const SizedBox(height: 12),
    FilledButton.icon(onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => GoalsSheet(data: data)), icon: const Icon(Icons.edit_outlined), label: const Text('Editar metas')),
  ]));
}

class GoalsSheet extends StatefulWidget { const GoalsSheet({super.key, required this.data}); final AppData data; @override State<GoalsSheet> createState() => _GoalsSheetState(); }
class _GoalsSheetState extends State<GoalsSheet> { late final TextEditingController daily; late final TextEditingController weekly; late final TextEditingController monthly; @override void initState(){super.initState();daily=TextEditingController(text:widget.data.dailyGoal.toStringAsFixed(0));weekly=TextEditingController(text:widget.data.weeklyGoal.toStringAsFixed(0));monthly=TextEditingController(text:widget.data.monthlyGoal.toStringAsFixed(0));} @override void dispose() { daily.dispose(); weekly.dispose(); monthly.dispose(); super.dispose(); } @override Widget build(BuildContext context) => Padding(padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom), child: Column(mainAxisSize: MainAxisSize.min, children: [Text('Editar metas', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), TextField(controller: daily, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Meta diária')), TextField(controller: weekly, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Meta semanal')), TextField(controller: monthly, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Meta mensal')), const SizedBox(height: 20), SizedBox(width: double.infinity, child: FilledButton(onPressed: () { final d = double.tryParse(daily.text); final w = double.tryParse(weekly.text); final m = double.tryParse(monthly.text); if (d != null && d > 0 && w != null && w > 0 && m != null && m > 0) { widget.data.updateGoals(daily: d, weekly: w, monthly: m); Navigator.pop(context); } }, child: const Text('Salvar metas')))])); }

class VehiclePage extends StatelessWidget {
  const VehiclePage({super.key, required this.data});
  final AppData data;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: data, builder: (context, _) => ListView(padding: const EdgeInsets.all(20), children: [
    Card(child: Padding(padding: const EdgeInsets.all(20), child: Row(children: [const CircleAvatar(radius: 28, child: Icon(Icons.directions_car, size: 30)), const SizedBox(width: 16), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Chevrolet Onix 2022', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)), Text('Flex · ${data.odometer.toStringAsFixed(0)} km')])]))),
    const SizedBox(height: 16),
    _InfoCard(icon: Icons.local_gas_station_outlined, title: 'Combustível', subtitle: 'Último abastecimento: ${_currency(data.fuelCost)} · ${data.fuelLiters.toStringAsFixed(1)} L'),
    _InfoCard(icon: Icons.build_outlined, title: 'Próxima troca de óleo', subtitle: 'Em 1.250 km ou 18 set.'),
    _InfoCard(icon: Icons.description_outlined, title: 'Documentos', subtitle: 'Licenciamento vence em dezembro'),
    const SizedBox(height: 12),
    FilledButton.icon(onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => FuelSheet(data: data)), icon: const Icon(Icons.local_gas_station), label: const Text('Registrar abastecimento')),
  ]));
}

class FuelSheet extends StatefulWidget { const FuelSheet({super.key, required this.data}); final AppData data; @override State<FuelSheet> createState() => _FuelSheetState(); }
class _FuelSheetState extends State<FuelSheet> { final liters = TextEditingController(); final cost = TextEditingController(); final km = TextEditingController(); @override void dispose(){liters.dispose();cost.dispose();km.dispose();super.dispose();} @override Widget build(BuildContext context) => Padding(padding: EdgeInsets.fromLTRB(24,24,24,24 + MediaQuery.of(context).viewInsets.bottom), child: Column(mainAxisSize: MainAxisSize.min, children:[Text('Registrar abastecimento',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),TextField(controller:liters,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Litros')),TextField(controller:cost,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Valor pago')),TextField(controller:km,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Quilometragem atual')),const SizedBox(height:20),SizedBox(width:double.infinity,child:FilledButton(onPressed:(){final l=double.tryParse(liters.text.replaceAll(',','.'));final c=double.tryParse(cost.text.replaceAll(',','.'));final k=double.tryParse(km.text.replaceAll(',','.'));if(l!=null&&l>0&&c!=null&&c>0&&k!=null&&k>=widget.data.odometer){widget.data.addFuel(liters:l,cost:c,kilometers:k);Navigator.pop(context);}},child:const Text('Salvar abastecimento')))])); }

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key, required this.data});
  final AppData data;
  @override State<AssistantPage> createState() => _AssistantPageState();
}
class _AssistantPageState extends State<AssistantPage> {
  final question = TextEditingController();
  String? answer;
  @override void dispose() { question.dispose(); super.dispose(); }
  void respond([String? prompt]) { final q = (prompt ?? question.text).toLowerCase(); setState(() { if (q.contains('meta')) { answer = 'Faltam ${_currency((widget.data.dailyGoal - widget.data.income).clamp(0, double.infinity).toDouble())} para sua meta diária.'; } else if (q.contains('combust') || q.contains('gasto')) { answer = 'Hoje seus gastos são ${_currency(widget.data.expense)}. O combustível registrado foi ${_currency(widget.data.fuelCost)}.'; } else { answer = 'Seu lucro líquido é ${_currency(widget.data.balance)}. Mantenha os lançamentos atualizados para recomendações mais precisas.'; } }); }
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const CircleAvatar(radius: 28, child: Icon(Icons.auto_awesome, size: 28)),
      const SizedBox(height: 16),
      Text('Assistente Motorista Pro', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      const Text('Use seus dados de ganhos, custos e metas para receber orientações práticas.'),
      const SizedBox(height: 24),
      _Suggestion(text: 'Quanto falta para minha meta de hoje?', onTap: () => respond('meta')),
      _Suggestion(text: 'Como estão meus gastos com combustível?', onTap: () => respond('combustível')),
      _Suggestion(text: 'Monte um plano para atingir a meta semanal.', onTap: () => respond('meta semanal')),
      if (answer != null) Card(color: Theme.of(context).colorScheme.primaryContainer, child: Padding(padding: const EdgeInsets.all(16), child: Text(answer!))),
      const Spacer(),
      TextField(controller: question, onSubmitted: (_) => respond(), decoration: InputDecoration(hintText: 'Pergunte ao assistente...', suffixIcon: IconButton(onPressed: respond, icon: const Icon(Icons.send)), border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16)))),),
    ],
  ));
}

class CalculatorSettingsPage extends StatefulWidget {
  const CalculatorSettingsPage({super.key, required this.data, required this.notifications});
  final AppData data;
  final RideNotificationService notifications;

  @override
  State<CalculatorSettingsPage> createState() => _CalculatorSettingsPageState();
}

class _CalculatorSettingsPageState extends State<CalculatorSettingsPage> with WidgetsBindingObserver {
  late final TextEditingController yellow;
  late final TextEditingController green;
  bool notificationAccess = false;
  bool overlayAccess = false;
  bool accessibilityAccess = false;
  bool setupFlowActive = false;
  bool checkingSetup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    yellow = TextEditingController(text: widget.data.calculatorYellowPerKm.toStringAsFixed(2).replaceAll('.', ','));
    green = TextEditingController(text: widget.data.calculatorGreenPerKm.toStringAsFixed(2).replaceAll('.', ','));
    _refreshPermissions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Future<void>.delayed(const Duration(milliseconds: 700), () async {
        await _refreshPermissions();
        if (setupFlowActive) await _continueAutomaticSetup();
      });
    }
  }

  Future<void> _refreshPermissions() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final notifications = await widget.notifications.hasPermission();
    final overlay = await FlutterOverlayWindow.isPermissionGranted();
    final accessibility = await _nativeOverlay.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
    if (mounted) setState(() { notificationAccess = notifications; overlayAccess = overlay; accessibilityAccess = accessibility; });
  }

  double? _number(String value) => double.tryParse(value.trim().replaceAll(',', '.'));

  void _save() {
    final yellowValue = _number(yellow.text);
    final greenValue = _number(green.text);
    if (yellowValue == null || yellowValue <= 0 || greenValue == null || greenValue <= yellowValue) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe valores válidos. A meta verde precisa ser maior que a amarela.')));
      return;
    }
    widget.data.updateCalculator(yellowPerKm: yellowValue, greenPerKm: greenValue);
    _nativeOverlay.invokeMethod<void>('configureCalculator', {'yellow': yellowValue, 'green': greenValue});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configuração da calculadora salva.')));
  }

  Future<void> _requestNotifications() async {
    await widget.notifications.requestPermission();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _refreshPermissions();
  }

  Future<void> _requestOverlay() async {
    await FlutterOverlayWindow.requestPermission();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _refreshPermissions();
  }

  Future<void> _requestAccessibility() async {
    await _nativeOverlay.invokeMethod<void>('openAccessibilitySettings');
  }

  Future<void> _activateAutomaticCalculator() async {
    setupFlowActive = true;
    _save();
    await _continueAutomaticSetup();
  }

  Future<void> _continueAutomaticSetup() async {
    if (checkingSetup || !mounted) return;
    checkingSetup = true;
    try {
      await _refreshPermissions();
      if (!notificationAccess) {
        await widget.notifications.requestPermission();
        return;
      }
      if (!overlayAccess) {
        await FlutterOverlayWindow.requestPermission();
        return;
      }
      if (!accessibilityAccess) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Última autorização'),
            content: const Text('Na próxima tela, toque em “Motorista Pro – leitura de corridas” e ative Permitir. Depois volte ao aplicativo.'),
            actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Abrir autorização'))],
          ),
        );
        await _requestAccessibility();
        return;
      }
      setupFlowActive = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Calculadora automática ativada! Abra a 99 ou Uber.'),
          backgroundColor: Colors.green,
        ));
      }
    } finally {
      checkingSetup = false;
    }
  }

  Future<void> _preview() async {
    _save();
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      await _requestOverlay();
      return;
    }
    try {
      await _showNativeRideOverlay({'platform':'Teste 99/Uber','fare':24.50,'distance':8.2,'minutes':18,'perKm':2.99,'perHour':81.67,'yellow':widget.data.calculatorYellowPerKm,'green':widget.data.calculatorGreenPerKm});
    } on PlatformException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível abrir o cartão: ${error.message ?? error.code}')));
    }
  }

  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); yellow.dispose(); green.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Calculadora flutuante')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text('Configure a análise da corrida', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Quando uma oferta aparecer na tela da 99 ou Uber, o cartão calculará automaticamente valor, distância, tempo, ganho por km e ganho por hora.'),
      const SizedBox(height: 20),
      Card(color: Colors.red.shade50, child: const ListTile(leading: CircleAvatar(backgroundColor: Colors.red, child: Icon(Icons.close, color: Colors.white)), title: Text('Vermelho'), subtitle: Text('Abaixo do início da faixa amarela'))),
      Card(color: Colors.amber.shade50, child: const ListTile(leading: CircleAvatar(backgroundColor: Colors.amber, child: Icon(Icons.remove, color: Colors.black)), title: Text('Amarelo'), subtitle: Text('Entre o mínimo aceitável e a meta ideal'))),
      Card(color: Colors.green.shade50, child: const ListTile(leading: CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.check, color: Colors.white)), title: Text('Verde'), subtitle: Text('Igual ou acima da meta ideal'))),
      const SizedBox(height: 12),
      TextField(controller: yellow, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Faixa amarela começa em (R\$/km)', prefixIcon: Icon(Icons.warning_amber), border: OutlineInputBorder())),
      const SizedBox(height: 14),
      TextField(controller: green, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Meta verde começa em (R\$/km)', prefixIcon: Icon(Icons.flag), border: OutlineInputBorder())),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: _activateAutomaticCalculator,
        icon: Icon(notificationAccess && overlayAccess && accessibilityAccess ? Icons.check_circle : Icons.auto_fix_high),
        label: Text(notificationAccess && overlayAccess && accessibilityAccess ? 'Calculadora automática ativada' : 'Ativar calculadora automática'),
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: notificationAccess && overlayAccess && accessibilityAccess ? Colors.green : null),
      ),
      const SizedBox(height: 12),
      _PermissionTile(title: 'Leitura das notificações', enabled: notificationAccess, onTap: _requestNotifications),
      _PermissionTile(title: 'Aparecer sobre outros aplicativos', enabled: overlayAccess, onTap: _requestOverlay),
      _PermissionTile(title: 'Leitura da tela da 99 e Uber', enabled: accessibilityAccess, onTap: _requestAccessibility),
      const SizedBox(height: 18),
      FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Salvar configuração')),
      const SizedBox(height: 10),
      OutlinedButton.icon(onPressed: _preview, icon: const Icon(Icons.preview), label: const Text('Testar cartão flutuante')),
    ]),
  );
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({required this.title, required this.enabled, required this.onTap});
  final String title;
  final bool enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(child: ListTile(leading: Icon(enabled ? Icons.check_circle : Icons.error_outline, color: enabled ? Colors.green : Colors.orange), title: Text(title), subtitle: Text(enabled ? 'Autorizado' : 'Toque para autorizar'), trailing: const Icon(Icons.chevron_right), onTap: onTap));
}

class RideOverlayView extends StatefulWidget {
  const RideOverlayView({super.key});
  @override
  State<RideOverlayView> createState() => _RideOverlayViewState();
}

class _RideOverlayViewState extends State<RideOverlayView> {
  StreamSubscription<dynamic>? subscription;
  Map<String, dynamic> offer = const {
    'platform': 'Motorista Pro',
    'fare': 24.50,
    'distance': 8.2,
    'minutes': 18,
    'perKm': 2.99,
    'perHour': 81.67,
    'yellow': 1.50,
    'green': 2.00,
  };

  @override
  void initState() {
    super.initState();
    subscription = FlutterOverlayWindow.overlayListener.listen((event) {
      try {
        final decoded = jsonDecode(event.toString()) as Map<String, dynamic>;
        if (mounted) setState(() => offer = decoded);
      } catch (_) {}
    });
  }

  @override
  void dispose() { subscription?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final item = offer;
    final perKm = (item['perKm'] as num).toDouble();
    final yellow = (item['yellow'] as num).toDouble();
    final green = (item['green'] as num).toDouble();
    final isGreen = perKm >= green;
    final isYellow = perKm >= yellow && !isGreen;
    final color = isGreen ? const Color(0xFF16803C) : isYellow ? const Color(0xFFF4B400) : const Color(0xFFC62828);
    final status = isGreen ? 'ACIMA DA META' : isYellow ? 'FAIXA INTERMEDIÁRIA' : 'ABAIXO DA META';
    return Material(color: Colors.transparent, child: SafeArea(child: Container(
      margin: const EdgeInsets.all(8), padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10)]),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text('${item['platform']} · $status', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))), IconButton(onPressed: FlutterOverlayWindow.closeOverlay, icon: const Icon(Icons.close, color: Colors.white), visualDensity: VisualDensity.compact)]),
        Text(_currency((item['fare'] as num).toDouble()), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 28)),
        Text('${(item['distance'] as num).toStringAsFixed(1)} km  •  ${item['minutes']} min  •  ${_currency(perKm)}/km  •  ${_currency((item['perHour'] as num).toDouble())}/h', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    )));
  }
}

class RideOfferDialog extends StatelessWidget {
  const RideOfferDialog({super.key, required this.offer});
  final RideOffer offer;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Nova corrida · ${offer.platform}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_currency(offer.fare), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _RideMetric(label: 'Distância', value: '${offer.distanceKm.toStringAsFixed(1)} km'),
          _RideMetric(label: 'Duração', value: '${offer.durationMinutes} min'),
          _RideMetric(label: 'Ganho por km', value: _currency(offer.earningsPerKm)),
          _RideMetric(label: 'Ganho por hora', value: _currency(offer.earningsPerHour)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Descartar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Registrar corrida')),
        ],
      );
}

class _RideMetric extends StatelessWidget {
  const _RideMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))]),
      );
}
class ReportsPage extends StatelessWidget { const ReportsPage({super.key, required this.data}); final AppData data; @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Relatórios')), body: AnimatedBuilder(animation:data,builder:(context,_)=>ListView(padding:const EdgeInsets.all(20),children:[Text('Resumo financeiro',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:16),_InfoCard(icon:Icons.account_balance_wallet_outlined,title:'Receitas',subtitle:_currency(data.income)),_InfoCard(icon:Icons.money_off_outlined,title:'Despesas',subtitle:_currency(data.expense)),_InfoCard(icon:Icons.savings_outlined,title:'Lucro líquido',subtitle:_currency(data.balance)),_InfoCard(icon:Icons.local_gas_station_outlined,title:'Custo por combustível',subtitle:_currency(data.fuelCost)),const SizedBox(height:12),FilledButton.icon(onPressed:()=>ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Exportação PDF/CSV será conectada ao serviço de relatórios.'))),icon:const Icon(Icons.file_download_outlined),label:const Text('Exportar relatório'))]))); }
class RemindersPage extends StatefulWidget { const RemindersPage({super.key,required this.data}); final AppData data; @override State<RemindersPage> createState()=>_RemindersPageState(); }
class _RemindersPageState extends State<RemindersPage> { final controller=TextEditingController(); @override void dispose(){controller.dispose();super.dispose();} @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Agenda e lembretes')),body:AnimatedBuilder(animation:widget.data,builder:(context,_)=>ListView(padding:const EdgeInsets.all(20),children:[...widget.data.reminders.map((r)=>Card(child:ListTile(leading:const Icon(Icons.notifications_active_outlined),title:Text(r),trailing:IconButton(icon:const Icon(Icons.check_circle_outline),tooltip:'Concluir lembrete',onPressed:()=>widget.data.removeReminder(r))))),const SizedBox(height:16),TextField(controller:controller,onSubmitted:(_)=>_add(),decoration:InputDecoration(labelText:'Novo lembrete',suffixIcon:IconButton(icon:const Icon(Icons.add),onPressed:_add)))]))); void _add(){widget.data.addReminder(controller.text);controller.clear();} }
class _Suggestion extends StatelessWidget { const _Suggestion({required this.text, required this.onTap}); final String text; final VoidCallback onTap; @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 10), child: OutlinedButton(onPressed: onTap, child: Align(alignment: Alignment.centerLeft, child: Text(text)))); }
class _InfoCard extends StatelessWidget { const _InfoCard({required this.icon, required this.title, required this.subtitle}); final IconData icon; final String title, subtitle; @override Widget build(BuildContext context) => Card(child: ListTile(leading: Icon(icon, color: Theme.of(context).colorScheme.primary), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right))); }
class _BalanceCard extends StatelessWidget { const _BalanceCard({required this.value}); final double value; @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(24)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Lucro líquido hoje', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .8))), const SizedBox(height: 8), Text(_currency(value), style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Theme.of(context).colorScheme.onPrimary, fontWeight: FontWeight.bold))])); }
class _MetricCard extends StatelessWidget { const _MetricCard({required this.label, required this.value, required this.icon, required this.color}); final String label; final double value; final IconData icon; final Color color; @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: color), const SizedBox(height: 12), Text(label), Text(_currency(value), style: const TextStyle(fontWeight: FontWeight.bold))]))); }
class _GoalCard extends StatelessWidget { const _GoalCard({required this.progress, required this.current, required this.goal}); final double progress, current, goal; @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Meta diária', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text('${_currency(current)} de ${_currency(goal)}'), const SizedBox(height: 12), LinearProgressIndicator(value: progress, minHeight: 10, borderRadius: BorderRadius.circular(10)), const SizedBox(height: 8), Text('${(progress * 100).toStringAsFixed(0)}% concluído')]))); }
class _EntryTile extends StatelessWidget { const _EntryTile({required this.entry}); final TransactionEntry entry; @override Widget build(BuildContext context) => Card(child: ListTile(leading: CircleAvatar(backgroundColor: entry.isIncome ? Colors.green.withValues(alpha: .12) : Colors.red.withValues(alpha: .12), child: Icon(entry.isIncome ? Icons.add : Icons.remove, color: entry.isIncome ? Colors.green : Colors.red)), title: Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text('${entry.date.day.toString().padLeft(2, '0')}/${entry.date.month.toString().padLeft(2, '0')} · ${entry.date.hour.toString().padLeft(2, '0')}:${entry.date.minute.toString().padLeft(2, '0')}'), trailing: Text('${entry.isIncome ? '+' : '-'} ${_currency(entry.value)}', style: TextStyle(color: entry.isIncome ? Colors.green : Colors.red, fontWeight: FontWeight.bold)))); }
String _currency(double value) => NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
