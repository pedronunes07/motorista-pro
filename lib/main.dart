import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/ride_notification_service.dart';
import 'auth_gate.dart';
import 'models/profit_calculator.dart';
import 'models/completed_ride.dart';
import 'completed_rides_page.dart';
import 'route_risk_settings.dart';
export 'models/completed_ride.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MotoristaProApp());
}

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: RideOverlayView()));
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
        home: const AuthGate(),
      );
}

class TransactionEntry {
  const TransactionEntry({
    required this.title,
    required this.category,
    required this.value,
    required this.isIncome,
    required this.date,
    this.countsInTotals = true,
  });
  final String title;
  final String category;
  final double value;
  final bool isIncome;
  final bool countsInTotals;
  final DateTime date;
}

class AppData extends ChangeNotifier {
  final List<TransactionEntry> _entries = [];
  CompletedRideRepository? _rideRepository;
  bool get isLoaded => _rideRepository != null;
  List<CompletedRide> get completedRides => _rideRepository?.rides ?? const [];
  String? rideSyncError;
  List<TransactionEntry> get entries => [
    ..._entries.where((entry) => entry.countsInTotals || !completedRides.any((ride) => entry.category == 'Corridas' && entry.date == ride.date && entry.title == '${ride.platform} · corrida finalizada')),
    ...completedRides.where((r) => r.countsInTotals).map((r) => TransactionEntry(title: '${r.platform} · corrida finalizada', category: 'Corridas', value: r.value!, isIncome: true, date: r.date)),
  ]..sort((a, b) => b.date.compareTo(a.date));
  double dailyGoal = 0;
  double weeklyGoal = 0;
  double monthlyGoal = 0;
  double odometer = 0;
  double fuelLiters = 0;
  double fuelCost = 0;
  final List<String> reminders = [];
  double calculatorYellowPerKm = 1.50;
  double calculatorGreenPerKm = 2.00;
  double passengerRatingMinimum = 4.80;
  String vehicleBrand = '';
  String vehicleModel = '';
  String vehicleYear = '';
  String vehicleFuel = '';
  String vehiclePlate = '';
  String vehicleImagePath = '';

  double get income => entries.where((e) => e.isIncome && e.countsInTotals).fold(0, (sum, e) => sum + e.value);
  double get expense => entries.where((e) => !e.isIncome).fold(0, (sum, e) => sum + e.value);
  double get balance => income - expense;
  double get goalProgress => dailyGoal > 0 ? (income / dailyGoal).clamp(0, 1) : 0;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('startedEmptyV2') ?? false)) {
      await prefs.setBool('startedEmptyV2', true);
    }
    dailyGoal = prefs.getDouble('dailyGoal') ?? dailyGoal;
    weeklyGoal = prefs.getDouble('weeklyGoal') ?? weeklyGoal;
    monthlyGoal = prefs.getDouble('monthlyGoal') ?? monthlyGoal;
    odometer = prefs.getDouble('odometer') ?? odometer;
    fuelLiters = prefs.getDouble('fuelLiters') ?? fuelLiters;
    fuelCost = prefs.getDouble('fuelCost') ?? fuelCost;
    calculatorYellowPerKm = prefs.getDouble('calculatorYellowPerKm') ?? calculatorYellowPerKm;
    calculatorGreenPerKm = prefs.getDouble('calculatorGreenPerKm') ?? calculatorGreenPerKm;
    passengerRatingMinimum = prefs.getDouble('passengerRatingMinimum') ?? passengerRatingMinimum;
    vehicleBrand = prefs.getString('vehicleBrand') ?? '';
    vehicleModel = prefs.getString('vehicleModel') ?? '';
    vehicleYear = prefs.getString('vehicleYear') ?? '';
    vehicleFuel = prefs.getString('vehicleFuel') ?? '';
    vehiclePlate = prefs.getString('vehiclePlate') ?? '';
    vehicleImagePath = prefs.getString('vehicleImagePath') ?? '';
    reminders
      ..clear()
      ..addAll(prefs.getStringList('reminders') ?? []);
    final rawEntries = prefs.getString('entries');
    if (rawEntries != null) {
      final saved = jsonDecode(rawEntries) as List<dynamic>;
      _entries
        ..clear()
        ..addAll(saved.map((item) {
          final map = item as Map<String, dynamic>;
          return TransactionEntry(title: map['title'] as String, category: map['category'] as String, value: (map['value'] as num).toDouble(), isIncome: map['income'] as bool, date: DateTime.parse(map['date'] as String), countsInTotals: map['countsInTotals'] as bool? ?? !(map['category'] == 'Corridas' && (map['title'] as String).endsWith('· corrida finalizada')));
        }));
    }
    final rawRides = prefs.getString('completedRidesV27') ?? prefs.getString('completedRides');
    final saved = rawRides == null ? <dynamic>[] : jsonDecode(rawRides) as List<dynamic>;
    _rideRepository = CompletedRideRepository(
      initial: saved.map((r) => CompletedRide.fromJson(Map<String,dynamic>.from(r as Map))).toList(),
      write: (json) => prefs.setString('completedRidesV27', json),
    );
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
    await prefs.setDouble('passengerRatingMinimum', passengerRatingMinimum);
    await prefs.setString('vehicleBrand', vehicleBrand);
    await prefs.setString('vehicleModel', vehicleModel);
    await prefs.setString('vehicleYear', vehicleYear);
    await prefs.setString('vehicleFuel', vehicleFuel);
    await prefs.setString('vehiclePlate', vehiclePlate);
    await prefs.setString('vehicleImagePath', vehicleImagePath);
    await prefs.setStringList('reminders', reminders);
    await prefs.setString('entries', jsonEncode(_entries.map((e) => {'countsInTotals': e.countsInTotals, 'title': e.title, 'category': e.category, 'value': e.value, 'income': e.isIncome, 'date': e.date.toIso8601String()}).toList()));
  }

  Future<void> saveCompletedRides(List<CompletedRide> rides) async {
    await _rideRepository!.upsert(rides);
    rideSyncError = null;
    notifyListeners();
  }

  void setRideSyncError(String? error) { rideSyncError = error; notifyListeners(); }

  void add(TransactionEntry entry) {
    _entries.insert(0, entry);
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

  void updateCalculator({required double yellowPerKm, required double greenPerKm, required double minimumRating}) {
    calculatorYellowPerKm = yellowPerKm;
    calculatorGreenPerKm = greenPerKm;
    passengerRatingMinimum = minimumRating;
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

  void updateVehicle({required String brand, required String model, required String year, required String fuel, required String plate, String? imagePath}) {
    vehicleBrand = brand.trim();
    vehicleModel = model.trim();
    vehicleYear = year.trim();
    vehicleFuel = fuel.trim();
    vehiclePlate = plate.trim().toUpperCase();
    if (imagePath != null) vehicleImagePath = imagePath;
    _save();
    notifyListeners();
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final data = AppData();
  final rideNotifications = RideNotificationService();
  StreamSubscription<RideOffer>? rideSubscription;
  Timer? completedRideTimer;
  bool _syncingRides = false;
  int index = 0;
  late final List<Widget> pages;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeData();
    if (_supportsRideDetection) {
      rideNotifications.start();
      rideSubscription = rideNotifications.offers.listen(_showRideOffer);
    }
    pages = [Dashboard(data: data), CompletedRidesPage(data: data, onRetry: _syncCompletedRides), TransactionsPage(data: data), GoalsPage(data: data), VehiclePage(data: data), AssistantPage(data: data)];
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkCalculatorSetup());
  }

  Future<void> _initializeData() async {
    await data.load();
    if (!mounted) return;
    await _syncCompletedRides();
    completedRideTimer = Timer.periodic(const Duration(seconds: 5), (_) => _syncCompletedRides());
  }

  Future<void> _syncCompletedRides() async {
    if (!_supportsRideDetection || _syncingRides || !data.isLoaded || !mounted) return;
    _syncingRides = true;
    try {
      final pending = await _nativeOverlay.invokeMethod<List<dynamic>>('peekCompletedRides') ?? const [];
      final rides = pending.map((item) => CompletedRide.fromJson(Map<String,dynamic>.from(item as Map))).toList();
      if (rides.isNotEmpty) {
        await data.saveCompletedRides(rides);
        await _nativeOverlay.invokeMethod<bool>('acknowledgeCompletedRides', rides.map((r) => {'id': r.id, 'revision': r.revision}).toList());
      }
      data.setRideSyncError(null);
    } catch (_) {
      if (mounted) data.setRideSyncError('Não foi possível sincronizar. As corridas aguardam nova tentativa neste aparelho.');
    } finally { _syncingRides = false; }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncCompletedRides();
  }

  bool get _supportsRideDetection => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _checkCalculatorSetup() async {
    if (!_supportsRideDetection || !mounted) return;
    final notifications = await rideNotifications.hasPermission();
    final overlay = await FlutterOverlayWindow.isPermissionGranted();
    final accessibility = await _nativeOverlay.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
    final screenCapture = await _nativeOverlay.invokeMethod<bool>('isScreenCaptureActive') ?? false;
    if ((notifications && overlay && accessibility && screenCapture) || !mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ative a calculadora'),
        content: const Text('A instalação nova precisa receber novamente as permissões para mostrar os cálculos sobre a 99 e a Uber.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Depois')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ativar agora')),
        ],
      ),
    );
    if (open == true && mounted) await _openCalculatorSettings();
  }

  Future<void> _showRideOffer(RideOffer offer) async {
    if (!mounted) return;
    await _showRideOverlay(offer);
    // An offer is never booked as income. Completion is imported from its receipt.
  }

  Future<void> _showRideOverlay(RideOffer offer) async {
    if (!_supportsRideDetection || !await FlutterOverlayWindow.isPermissionGranted()) return;
    final prefs = await SharedPreferences.getInstance();
    await _showNativeRideOverlay({
      'platform': offer.platform,
      'fare': offer.fare,
      'distance': offer.distanceKm,
      'minutes': offer.durationMinutes,
      'perKm': offer.earningsPerKm,
      'perHour': offer.earningsPerHour,
      'yellow': data.calculatorYellowPerKm,
      'green': data.calculatorGreenPerKm,
      'ratingMinimum': data.passengerRatingMinimum,
      'theme': prefs.getInt('cardTheme') ?? 0,
      'fontScale': prefs.getDouble('cardFontScale') ?? 1,
      'cardScale': prefs.getDouble('cardScale') ?? 1,
    });
  }

  Future<void> _openCalculatorSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CalculatorSettingsPage(data: data, notifications: rideNotifications)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    completedRideTimer?.cancel();
    rideSubscription?.cancel();
    rideNotifications.dispose();
    data.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    const titles = ['Visão geral', 'Corridas finalizadas', 'Movimentações', 'Metas', 'Veículo', 'Assistente IA'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[index], style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout), tooltip: 'Sair'),
          IconButton(onPressed: _openCalculatorSettings, icon: const Icon(Icons.tune), tooltip: 'Configurar calculadora flutuante'),
          IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfitCalculatorPage(data: data))), icon: const Icon(Icons.calculate_outlined), tooltip: 'Lucro e custo por km'),
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
          NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Corridas'),
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
            Text('Olá, motorista 👋', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
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

class VehiclePage extends StatefulWidget {
  const VehiclePage({super.key, required this.data});
  final AppData data;
  @override State<VehiclePage> createState() => _VehiclePageState();
}

class _VehiclePageState extends State<VehiclePage> {
  final picker = ImagePicker();

  Future<void> _photo(ImageSource source) async {
    final image = await picker.pickImage(source: source, imageQuality: 82, maxWidth: 1600);
    if (image != null) widget.data.updateVehicle(brand: widget.data.vehicleBrand, model: widget.data.vehicleModel, year: widget.data.vehicleYear, fuel: widget.data.vehicleFuel, plate: widget.data.vehiclePlate, imagePath: image.path);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: widget.data, builder: (context, _) => ListView(padding: const EdgeInsets.all(20), children: [
    if (widget.data.vehicleImagePath.isNotEmpty && File(widget.data.vehicleImagePath).existsSync())
      ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.file(File(widget.data.vehicleImagePath), height: 210, width: double.infinity, fit: BoxFit.cover))
    else
      Container(height: 180, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.directions_car, size: 76)),
    const SizedBox(height: 12),
    Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () => _photo(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: const Text('Câmera'))), const SizedBox(width: 10), Expanded(child: OutlinedButton.icon(onPressed: () => _photo(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('Galeria')))]),
    const SizedBox(height: 12),
    Card(child: ListTile(leading: const Icon(Icons.directions_car), title: Text(widget.data.vehicleModel.isEmpty ? 'Nenhum veículo cadastrado' : '${widget.data.vehicleBrand} ${widget.data.vehicleModel} ${widget.data.vehicleYear}'.trim(), style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(widget.data.vehicleModel.isEmpty ? 'Toque em editar para cadastrar' : '${widget.data.vehicleFuel} · ${widget.data.vehiclePlate} · ${widget.data.odometer.toStringAsFixed(0)} km'), trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => VehicleEditSheet(data: widget.data))))),
    const SizedBox(height: 16),
    _InfoCard(icon: Icons.local_gas_station_outlined, title: 'Combustível', subtitle: widget.data.fuelCost == 0 ? 'Nenhum abastecimento registrado' : 'Último: ${_currency(widget.data.fuelCost)} · ${widget.data.fuelLiters.toStringAsFixed(1)} L'),
    const SizedBox(height: 12),
    FilledButton.icon(onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => VehicleEditSheet(data: widget.data)), icon: const Icon(Icons.edit), label: const Text('Cadastrar ou editar veículo')),
    const SizedBox(height: 10),
    OutlinedButton.icon(onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => FuelSheet(data: widget.data)), icon: const Icon(Icons.local_gas_station), label: const Text('Registrar abastecimento')),
  ]));
}

class VehicleEditSheet extends StatefulWidget {
  const VehicleEditSheet({super.key, required this.data}); final AppData data;
  @override State<VehicleEditSheet> createState() => _VehicleEditSheetState();
}
class _VehicleEditSheetState extends State<VehicleEditSheet> {
  late final TextEditingController brand, model, year, fuel, plate, km;
  @override void initState(){super.initState();brand=TextEditingController(text:widget.data.vehicleBrand);model=TextEditingController(text:widget.data.vehicleModel);year=TextEditingController(text:widget.data.vehicleYear);fuel=TextEditingController(text:widget.data.vehicleFuel);plate=TextEditingController(text:widget.data.vehiclePlate);km=TextEditingController(text:widget.data.odometer == 0 ? '' : widget.data.odometer.toStringAsFixed(0));}
  @override void dispose(){brand.dispose();model.dispose();year.dispose();fuel.dispose();plate.dispose();km.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Padding(padding:EdgeInsets.fromLTRB(20,20,20,20+MediaQuery.of(context).viewInsets.bottom),child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[Text('Dados do veículo',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),TextField(controller:brand,decoration:const InputDecoration(labelText:'Marca')),TextField(controller:model,decoration:const InputDecoration(labelText:'Modelo')),TextField(controller:year,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Ano')),TextField(controller:fuel,decoration:const InputDecoration(labelText:'Combustível')),TextField(controller:plate,textCapitalization:TextCapitalization.characters,decoration:const InputDecoration(labelText:'Placa')),TextField(controller:km,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Quilometragem')),const SizedBox(height:18),SizedBox(width:double.infinity,child:FilledButton(onPressed:(){if(model.text.trim().isEmpty)return;widget.data.odometer=double.tryParse(km.text.replaceAll(',','.'))??0;widget.data.updateVehicle(brand:brand.text,model:model.text,year:year.text,fuel:fuel.text,plate:plate.text);Navigator.pop(context);},child:const Text('Salvar veículo')))])));
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
  final apiKey = TextEditingController();
  String? answer;
  bool loading = false;
  bool showKey = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      apiKey.text = prefs.getString('openAiApiKey') ?? '';
      if (mounted) setState(() {});
    });
  }

  @override void dispose() { question.dispose(); apiKey.dispose(); super.dispose(); }

  String _localAnswer(String prompt) {
    final q = prompt.toLowerCase();
    final remaining = (widget.data.dailyGoal - widget.data.income).clamp(0, double.infinity).toDouble();
    if (q.contains('meta semanal')) {
      const days = 5;
      final double perDay = widget.data.weeklyGoal > 0 ? widget.data.weeklyGoal / days : 0.0;
      return widget.data.weeklyGoal > 0
          ? 'Para atingir ${_currency(widget.data.weeklyGoal)} na semana, busque cerca de ${_currency(perDay)} por dia em $days dias. Até agora foram registrados ${_currency(widget.data.income)}.'
          : 'Cadastre sua meta semanal na aba Metas para eu montar um plano diário preciso.';
    }
    if (q.contains('meta')) return remaining > 0 ? 'Faltam ${_currency(remaining)} para sua meta diária.' : 'Sua meta diária já foi atingida. Ótimo trabalho!';
    if (q.contains('combust') || q.contains('gasto') || q.contains('custo')) return 'Seus gastos registrados são ${_currency(widget.data.expense)}. O último abastecimento registrado foi ${_currency(widget.data.fuelCost)}.';
    if (q.contains('lucro') || q.contains('ganho')) return 'O saldo líquido registrado é ${_currency(widget.data.balance)}: ${_currency(widget.data.income)} de ganhos menos ${_currency(widget.data.expense)} de despesas.';
    return 'Com os dados registrados, seu saldo líquido é ${_currency(widget.data.balance)}. Pergunte sobre lucro, combustível, gastos ou metas para uma análise direta.';
  }

  Future<String> _askOnline(String prompt, String key) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(Uri.parse('https://api.openai.com/v1/responses'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      request.headers.contentType = ContentType.json;
      final context = 'Você é o assistente financeiro do app Motorista Pro. Responda em português brasileiro, de forma curta, prática e sem inventar valores. Dados reais registrados: ganhos ${widget.data.income}, despesas ${widget.data.expense}, saldo ${widget.data.balance}, combustível ${widget.data.fuelCost}, meta diária ${widget.data.dailyGoal}, meta semanal ${widget.data.weeklyGoal}.';
      request.write(jsonEncode({'model': 'gpt-5-mini', 'instructions': context, 'input': prompt, 'max_output_tokens': 350}));
      final response = await request.close().timeout(const Duration(seconds: 30));
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        throw Exception(((decoded['error'] as Map?)?['message'] ?? 'Falha ${response.statusCode}').toString());
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final output = decoded['output'] as List<dynamic>? ?? const [];
      for (final item in output) {
        final content = (item as Map<String, dynamic>)['content'] as List<dynamic>? ?? const [];
        for (final part in content) {
          final map = part as Map<String, dynamic>;
          if (map['type'] == 'output_text' && map['text'] is String) return map['text'] as String;
        }
      }
      throw Exception('A IA não retornou texto.');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> respond([String? suggestion]) async {
    final prompt = (suggestion ?? question.text).trim();
    if (prompt.isEmpty || loading) return;
    setState(() { loading = true; answer = null; });
    final prefs = await SharedPreferences.getInstance();
    final key = apiKey.text.trim();
    await prefs.setString('openAiApiKey', key);
    try {
      final result = key.isEmpty ? _localAnswer(prompt) : await _askOnline(prompt, key);
      if (mounted) setState(() => answer = result);
    } catch (error) {
      if (mounted) setState(() => answer = '${_localAnswer(prompt)}\n\nA IA online não respondeu: ${error.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: ListView(children: [
      const CircleAvatar(radius: 28, child: Icon(Icons.auto_awesome, size: 28)),
      const SizedBox(height: 16),
      Text('Assistente Motorista Pro', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      const Text('Receba orientações com os valores reais registrados no aplicativo.'),
      const SizedBox(height: 16),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        leading: Icon(apiKey.text.isEmpty ? Icons.smart_toy_outlined : Icons.cloud_done, color: apiKey.text.isEmpty ? Colors.orange : Colors.green),
        title: Text(apiKey.text.isEmpty ? 'IA local ativa' : 'IA online configurada'),
        subtitle: Text(apiKey.text.isEmpty ? 'Funciona sem internet para cálculos básicos' : 'Usando sua chave da OpenAI'),
        children: [
          TextField(controller: apiKey, obscureText: !showKey, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: 'Sua chave da OpenAI (opcional)', helperText: 'A chave fica salva somente neste aparelho.', border: const OutlineInputBorder(), suffixIcon: IconButton(onPressed: () => setState(() => showKey = !showKey), icon: Icon(showKey ? Icons.visibility_off : Icons.visibility)))),
          const SizedBox(height: 8),
        ],
      ),
      const SizedBox(height: 12),
      _Suggestion(text: 'Quanto falta para minha meta de hoje?', onTap: () => respond('meta')),
      _Suggestion(text: 'Como estão meus gastos com combustível?', onTap: () => respond('combustível')),
      _Suggestion(text: 'Monte um plano para atingir a meta semanal.', onTap: () => respond('meta semanal')),
      if (loading) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
      if (answer != null) Card(color: Theme.of(context).colorScheme.primaryContainer, child: Padding(padding: const EdgeInsets.all(16), child: SelectableText(answer!))),
      const SizedBox(height: 20),
      TextField(controller: question, minLines: 1, maxLines: 4, onSubmitted: (_) => respond(), decoration: InputDecoration(hintText: 'Pergunte sobre seus ganhos e custos...', suffixIcon: IconButton(onPressed: loading ? null : () => respond(), icon: const Icon(Icons.send)), border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16)))),),
    ],
  ));
}

class ProfitCalculatorPage extends StatefulWidget { const ProfitCalculatorPage({super.key, required this.data}); final AppData data; @override State<ProfitCalculatorPage> createState()=>_ProfitCalculatorPageState(); }
class _ProfitCalculatorPageState extends State<ProfitCalculatorPage> {
  final days=TextEditingController(text:'5'),fuel=TextEditingController(),liters=TextEditingController(),km=TextEditingController(),consumption=TextEditingController(),revenue=TextEditingController(),other=TextEditingController(text:'0'); ProfitInputs? result;
  double n(TextEditingController c){final raw=c.text.trim().replaceAll('R\$','').replaceAll(' ','');final normalized=raw.contains(',')?raw.replaceAll('.','').replaceAll(',','.'):raw;return double.tryParse(normalized)??0;}
  Future<void> calculate() async { final p=await SharedPreferences.getInstance(); final fields={'profitDays':days,'profitFuel':fuel,'profitLiters':liters,'profitKm':km,'profitConsumption':consumption,'profitRevenue':revenue,'profitOther':other}; for(final e in fields.entries){await p.setString(e.key,e.value.text);} if(mounted)setState(()=>result=ProfitInputs(workDaysPerWeek:n(days).round().clamp(1,7),fuelCost:n(fuel),fuelLiters:n(liters),kilometers:n(km),consumptionKmPerLiter:n(consumption),grossRevenue:n(revenue),otherCosts:n(other))); }
  @override void initState(){super.initState();SharedPreferences.getInstance().then((p){final fields={'profitDays':days,'profitFuel':fuel,'profitLiters':liters,'profitKm':km,'profitConsumption':consumption,'profitRevenue':revenue,'profitOther':other};for(final e in fields.entries){e.value.text=p.getString(e.key)??e.value.text;}if(fuel.text.isEmpty&&widget.data.fuelCost>0)fuel.text=widget.data.fuelCost.toStringAsFixed(2);if(liters.text.isEmpty&&widget.data.fuelLiters>0)liters.text=widget.data.fuelLiters.toStringAsFixed(2);if(revenue.text.isEmpty&&widget.data.income>0)revenue.text=widget.data.income.toStringAsFixed(2);if(mounted)setState((){});});}
  @override void dispose(){for(final c in[days,fuel,liters,km,consumption,revenue,other]){c.dispose();}super.dispose();}
  Widget field(TextEditingController c,String label,{String? hint,IconData? icon})=>Padding(padding:const EdgeInsets.only(bottom:12),child:TextField(controller:c,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:label,hintText:hint,prefixIcon:icon==null?null:Icon(icon),border:const OutlineInputBorder())));
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Meu lucro real')),body:ListView(padding:const EdgeInsets.all(20),children:[
    Text('Calcule quanto realmente sobra',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),
    const SizedBox(height:6),const Text('Use valores do mesmo período. O aplicativo preenche o que já estiver registrado e nunca inventa dados.'),const SizedBox(height:18),
    _FormSection(title:'Sua rotina',icon:Icons.calendar_today,children:[field(days,'Dias trabalhados por semana',hint:'Ex.: 5')]),
    _FormSection(title:'Combustível',icon:Icons.local_gas_station,children:[field(fuel,'Valor do último abastecimento',hint:'Ex.: 300,00'),field(liters,'Litros abastecidos',hint:'Ex.: 50'),field(consumption,'Consumo do veículo (km/L)',hint:'Ex.: 12')]),
    _FormSection(title:'Resultado do período',icon:Icons.payments_outlined,children:[field(km,'Quilômetros rodados',hint:'Ex.: 600'),field(revenue,'Faturamento bruto',hint:'Ex.: 1.500,00'),field(other,'Outros custos',hint:'Manutenção, aluguel, seguro...')]),
    FilledButton.icon(onPressed:calculate,icon:const Icon(Icons.calculate),label:const Text('Ver meu lucro'),style:FilledButton.styleFrom(padding:const EdgeInsets.symmetric(vertical:16))),
    if(result case final r?)...[const SizedBox(height:20),Text('Seu resultado',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:10),if(!r.hasCostEstimate)const Card(child:ListTile(leading:Icon(Icons.info_outline),title:Text('Preencha valor, litros e consumo ou quilometragem para calcular o custo por km.')))else...[
      _ResultHero(value:_currency(r.netProfit),label:'Lucro líquido do período',positive:r.netProfit>=0),
      GridView.count(crossAxisCount:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),childAspectRatio:1.35,mainAxisSpacing:10,crossAxisSpacing:10,children:[_ResultMetric(label:'Custo por km',value:_currency(r.costPerKm),icon:Icons.local_gas_station),_ResultMetric(label:'Lucro por km',value:r.hasProfitEstimate?_currency(r.profitPerKm):'Faltam dados',icon:Icons.route),_ResultMetric(label:'Por dia',value:r.hasProfitEstimate?_currency(r.dailyNet):'Faltam dados',icon:Icons.today),_ResultMetric(label:'Por semana',value:r.hasProfitEstimate?_currency(r.weeklyNet):'Faltam dados',icon:Icons.date_range)]),
      if(r.hasProfitEstimate)Card(child:ListTile(leading:const Icon(Icons.calendar_month),title:const Text('Projeção mensal'),subtitle:const Text('Média de 52 semanas ÷ 12 meses'),trailing:Text(_currency(r.monthlyNet),style:const TextStyle(fontWeight:FontWeight.bold))))
    ]]
  ]));
}

class _FormSection extends StatelessWidget { const _FormSection({required this.title,required this.icon,required this.children});final String title;final IconData icon;final List<Widget> children;@override Widget build(BuildContext context)=>Card(margin:const EdgeInsets.only(bottom:14),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Icon(icon,color:Theme.of(context).colorScheme.primary),const SizedBox(width:8),Text(title,style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.bold))]),const SizedBox(height:14),...children])));}
class _ResultHero extends StatelessWidget { const _ResultHero({required this.value,required this.label,required this.positive});final String value,label;final bool positive;@override Widget build(BuildContext context)=>Card(color:positive?Colors.green.shade50:Colors.red.shade50,child:Padding(padding:const EdgeInsets.all(20),child:Column(children:[Text(label),const SizedBox(height:6),Text(value,style:Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.bold,color:positive?Colors.green.shade800:Colors.red.shade800))])));}
class _ResultMetric extends StatelessWidget { const _ResultMetric({required this.label,required this.value,required this.icon});final String label,value;final IconData icon;@override Widget build(BuildContext context)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(icon,color:Theme.of(context).colorScheme.primary),const SizedBox(height:6),Text(label,textAlign:TextAlign.center),const SizedBox(height:4),Text(value,textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.bold))])));}

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
  late final TextEditingController rating;
  bool notificationAccess = false;
  bool overlayAccess = false;
  bool accessibilityAccess = false;
  bool screenCaptureAccess = false;
  bool setupFlowActive = false;
  bool checkingSetup = false;
  int cardTheme = 0; double fontScale = 1, cardScale = 1;
  Timer? liveSaveTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    yellow = TextEditingController(text: widget.data.calculatorYellowPerKm.toStringAsFixed(2).replaceAll('.', ','));
    green = TextEditingController(text: widget.data.calculatorGreenPerKm.toStringAsFixed(2).replaceAll('.', ','));
    rating = TextEditingController(text: widget.data.passengerRatingMinimum.toStringAsFixed(2).replaceAll('.', ','));
    SharedPreferences.getInstance().then((p){if(mounted)setState((){cardTheme=p.getInt('cardTheme')??0;fontScale=p.getDouble('cardFontScale')??1;cardScale=p.getDouble('cardScale')??1;});});
    for (final controller in [yellow, green, rating]) { controller.addListener(_scheduleLiveSave); }
    _refreshPermissions();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showLastCrash());
  }

  Future<void> _showLastCrash() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android || !mounted) return;
    final report = await _nativeOverlay.invokeMethod<String>('getLastCrash') ?? '';
    if (report.isEmpty || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Encontramos a causa do fechamento'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(report)),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Diagnóstico copiado. Envie esse texto para mim.')));
            },
            child: const Text('Copiar diagnóstico'),
          ),
          FilledButton(
            onPressed: () async {
              await _nativeOverlay.invokeMethod<void>('clearLastCrash');
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
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
    final screenCapture = await _nativeOverlay.invokeMethod<bool>('isScreenCaptureActive') ?? false;
    if (mounted) setState(() { notificationAccess = notifications; overlayAccess = overlay; accessibilityAccess = accessibility; screenCaptureAccess = screenCapture; });
  }

  double? _number(String value) => double.tryParse(value.trim().replaceAll(',', '.'));

  void _scheduleLiveSave() {
    liveSaveTimer?.cancel();
    liveSaveTimer = Timer(const Duration(milliseconds: 250), () => _save(showMessage: false));
  }

  Future<bool> _save({bool showMessage = true}) async {
    final yellowValue = _number(yellow.text);
    final greenValue = _number(green.text);
    final ratingValue = _number(rating.text);
    if (yellowValue == null || yellowValue <= 0 || greenValue == null || greenValue <= yellowValue || ratingValue == null || ratingValue < 1 || ratingValue > 5) {
      if (showMessage) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe valores válidos. A meta verde deve ser maior que a amarela e a nota deve ficar entre 1 e 5.')));
      return false;
    }
    widget.data.updateCalculator(yellowPerKm: yellowValue, greenPerKm: greenValue, minimumRating: ratingValue);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('cardTheme',cardTheme); await prefs.setDouble('cardFontScale',fontScale); await prefs.setDouble('cardScale',cardScale);
    await _nativeOverlay.invokeMethod<void>('configureCalculator', {'yellow': yellowValue, 'green': greenValue, 'ratingMinimum': ratingValue,'theme':cardTheme,'fontScale':fontScale,'cardScale':cardScale});
    if (showMessage && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configuração salva e aplicada ao cartão.')));
    return true;
  }

  Future<void> _requestNotifications() async {
    try {
      await _nativeOverlay.invokeMethod<void>('openNotificationAccessSettings');
    } on PlatformException {
      await widget.notifications.requestPermission();
    }
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

  Future<void> _deactivateAutomaticCalculator() async {
    setupFlowActive = false;
    await _nativeOverlay.invokeMethod<bool>('stopScreenCapture');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _refreshPermissions();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Calculadora automática desligada.'),
      ));
    }
  }

  Future<void> _continueAutomaticSetup() async {
    if (checkingSetup || !mounted) return;
    checkingSetup = true;
    try {
      await _refreshPermissions();
      if (!notificationAccess) {
        await _requestNotifications();
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
      if (!screenCaptureAccess) {
        final started = await _nativeOverlay.invokeMethod<bool>('requestScreenCapture') ?? false;
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await _refreshPermissions();
        if (screenCaptureAccess && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Captura da tela ativada! Agora abra a 99.'),
            backgroundColor: Colors.green,
          ));
        } else if (!started && mounted) {
          final detail = await _nativeOverlay.invokeMethod<String>('getScreenCaptureError') ?? '';
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('A captura foi encerrada'),
              content: Text(detail.isEmpty
                  ? 'O celular encerrou a leitura da tela. Abra esta tela novamente e tente ativar.'
                  : 'Motivo informado pelo celular:\n\n$detail'),
              actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendi'))],
            ),
          );
        }
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
    if (!await _save(showMessage: false)) return;
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      await _requestOverlay();
      return;
    }
    try {
      await _showNativeRideOverlay({'platform':'Teste 99/Uber','fare':24.50,'distance':8.2,'minutes':18,'perKm':2.99,'perHour':81.67,'rating':4.72,'yellow':widget.data.calculatorYellowPerKm,'green':widget.data.calculatorGreenPerKm,'ratingMinimum':widget.data.passengerRatingMinimum,'theme':cardTheme,'fontScale':fontScale,'cardScale':cardScale});
    } on PlatformException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível abrir o cartão: ${error.message ?? error.code}')));
    }
  }

  @override
  void dispose() { liveSaveTimer?.cancel(); WidgetsBinding.instance.removeObserver(this); yellow.dispose(); green.dispose(); rating.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Calculadora flutuante')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text('Configure a análise da corrida', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const RouteRiskSettings(),
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
      const SizedBox(height: 14),
      TextField(controller: rating, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Nota mínima do passageiro', hintText: 'Ex.: 4,80', prefixIcon: Icon(Icons.star_outline), border: OutlineInputBorder())),
      const SizedBox(height:14),
      SegmentedButton<int>(segments:const[ButtonSegment(value:0,label:Text('Cores')),ButtonSegment(value:1,label:Text('Claro')),ButtonSegment(value:2,label:Text('Escuro'))],selected:{cardTheme},onSelectionChanged:(v){setState(()=>cardTheme=v.first);_scheduleLiveSave();}),
      ListTile(title:const Text('Tamanho da letra'),trailing:Text('${(fontScale*100).round()}%'),subtitle:Slider(value:fontScale,min:.8,max:1.5,divisions:7,onChanged:(v){setState(()=>fontScale=v);_scheduleLiveSave();})),
      ListTile(title:const Text('Tamanho do cartão'),trailing:Text('${(cardScale*100).round()}%'),subtitle:Slider(value:cardScale,min:.8,max:1.3,divisions:5,onChanged:(v){setState(()=>cardScale=v);_scheduleLiveSave();})),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: screenCaptureAccess ? _deactivateAutomaticCalculator : _activateAutomaticCalculator,
        icon: Icon(screenCaptureAccess ? Icons.power_settings_new : Icons.auto_fix_high),
        label: Text(screenCaptureAccess ? 'Desligar calculadora automática' : 'Ativar calculadora automática'),
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: screenCaptureAccess ? Colors.red : null),
      ),
      const SizedBox(height: 12),
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[const Icon(Icons.security_outlined),const SizedBox(width:8),Expanded(child:Text('Ativação simples',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.bold)))]),
        const SizedBox(height:6),
        const Text('Toque no botão abaixo. O Motorista Pro abrirá uma autorização por vez e mostrará exatamente o que falta.'),
        const SizedBox(height:14),
        _SimplePermissionStatus(label:'1. Acesso às notificações',enabled:notificationAccess),
        _SimplePermissionStatus(label:'2. Cartão sobre outros aplicativos',enabled:overlayAccess),
        _SimplePermissionStatus(label:'3. Leitura da tela da corrida',enabled:accessibilityAccess),
        _SimplePermissionStatus(label:'4. Captura da corrida',enabled:screenCaptureAccess),
        const SizedBox(height:12),
        SizedBox(width:double.infinity,child:FilledButton.icon(
          onPressed:_activateAutomaticCalculator,
          icon:Icon(notificationAccess&&overlayAccess&&accessibilityAccess&&screenCaptureAccess?Icons.check_circle:Icons.arrow_forward),
          label:Text(notificationAccess&&overlayAccess&&accessibilityAccess&&screenCaptureAccess?'Tudo pronto':'Autorizar próxima etapa'),
        )),
      ]))),
      const SizedBox(height: 18),
      FilledButton.icon(onPressed: () => _save(), icon: const Icon(Icons.save), label: const Text('Salvar configuração')),
      const SizedBox(height: 10),
      OutlinedButton.icon(onPressed: _preview, icon: const Icon(Icons.preview), label: const Text('Testar cartão flutuante')),
    ]),
  );
}

class _SimplePermissionStatus extends StatelessWidget {
  const _SimplePermissionStatus({required this.label,required this.enabled});
  final String label;
  final bool enabled;
  @override Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:6),
    child:Row(children:[
      Icon(enabled?Icons.check_circle:Icons.radio_button_unchecked,color:enabled?Colors.green:Colors.grey),
      const SizedBox(width:10),
      Expanded(child:Text(label)),
      Text(enabled?'Pronto':'Pendente',style:TextStyle(fontWeight:FontWeight.w600,color:enabled?Colors.green:Colors.orange.shade800)),
    ]),
  );
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
class _EntryTile extends StatelessWidget { const _EntryTile({required this.entry}); final TransactionEntry entry; @override Widget build(BuildContext context) => Card(child: ListTile(leading: CircleAvatar(backgroundColor: entry.isIncome ? Colors.green.withValues(alpha: .12) : Colors.red.withValues(alpha: .12), child: Icon(entry.isIncome ? Icons.add : Icons.remove, color: entry.isIncome ? Colors.green : Colors.red)), title: Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text('${entry.countsInTotals ? '' : 'Valor antigo: revisar em Corridas · '}${entry.date.day.toString().padLeft(2, '0')}/${entry.date.month.toString().padLeft(2, '0')} · ${entry.date.hour.toString().padLeft(2, '0')}:${entry.date.minute.toString().padLeft(2, '0')}'), trailing: Text('${entry.isIncome ? '+' : '-'} ${_currency(entry.value)}', style: TextStyle(color: entry.isIncome ? Colors.green : Colors.red, fontWeight: FontWeight.bold)))); }
String _currency(double value) => NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
