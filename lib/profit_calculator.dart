class ProfitInputs {
  const ProfitInputs({required this.days, required this.fuelCost, required this.liters, required this.km, required this.consumption, required this.revenue, required this.otherCosts});
  final int days; final double fuelCost, liters, km, consumption, revenue, otherCosts;
  double get fuelPrice => liters > 0 ? fuelCost / liters : 0;
  double get fuelPerKm => consumption > 0 ? fuelPrice / consumption : (km > 0 ? fuelCost / km : 0);
  double get costPerKm => fuelPerKm + (km > 0 ? otherCosts / km : 0);
  double get totalCost => km > 0 ? costPerKm * km : fuelCost + otherCosts;
  double get netProfit => revenue - totalCost;
  double get profitPerKm => km > 0 ? netProfit / km : 0;
  double get daily => days > 0 ? netProfit / days : 0;
  double get monthly => netProfit * 52 / 12;
  bool get hasCost => fuelCost > 0 && liters > 0 && (consumption > 0 || km > 0);
  bool get hasProfit => hasCost && revenue > 0 && km > 0;
}
