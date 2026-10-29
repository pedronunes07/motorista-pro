class ProfitInputs {
  const ProfitInputs({this.workDaysPerWeek=5,this.fuelCost=0,this.fuelLiters=0,this.kilometers=0,this.consumptionKmPerLiter=0,this.grossRevenue=0,this.otherCosts=0});
  final int workDaysPerWeek; final double fuelCost,fuelLiters,kilometers,consumptionKmPerLiter,grossRevenue,otherCosts;
  double get fuelPricePerLiter=>fuelLiters>0?fuelCost/fuelLiters:0;
  double get fuelCostPerKm=>consumptionKmPerLiter>0?fuelPricePerLiter/consumptionKmPerLiter:(kilometers>0?fuelCost/kilometers:0);
  double get costPerKm=>fuelCostPerKm+(kilometers>0?otherCosts/kilometers:0);
  double get totalCost=>kilometers>0?costPerKm*kilometers:fuelCost+otherCosts;
  double get netProfit=>grossRevenue-totalCost; double get profitPerKm=>kilometers>0?netProfit/kilometers:0;
  double get dailyNet=>workDaysPerWeek>0?netProfit/workDaysPerWeek:0; double get weeklyNet=>netProfit; double get monthlyNet=>weeklyNet*52/12;
  bool get hasCostEstimate=>fuelCost>0&&fuelLiters>0&&(consumptionKmPerLiter>0||kilometers>0);
  bool get hasProfitEstimate=>hasCostEstimate&&grossRevenue>0&&kilometers>0;
}
