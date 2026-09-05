import 'package:flutter_test/flutter_test.dart';
import 'package:motorista_pro/models/profit_calculator.dart';

void main() {
  test('calcula custo e projeções apenas com dados reais informados', () {
    const input = ProfitInputs(workDaysPerWeek: 5, fuelCost: 300, fuelLiters: 50, kilometers: 600, consumptionKmPerLiter: 12, grossRevenue: 1500, otherCosts: 120);
    expect(input.fuelPricePerLiter, 6);
    expect(input.costPerKm, closeTo(.7, .0001));
    expect(input.netProfit, closeTo(1080, .0001));
    expect(input.profitPerKm, closeTo(1.8, .0001));
    expect(input.dailyNet, 216);
  });

  test('não produz estimativa quando faltam dados', () {
    const input = ProfitInputs(fuelCost: 200);
    expect(input.hasCostEstimate, isFalse);
    expect(input.hasProfitEstimate, isFalse);
  });
}
