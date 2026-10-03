import 'package:flutter_test/flutter_test.dart';

import 'package:teamira/services/premium_service.dart';

void main() {
  group('PremiumPlanKind.seats', () {
    test('mirrors the backend PLAN_SEATS', () {
      expect(PremiumPlanKind.individual.seats, 1);
      expect(PremiumPlanKind.couple.seats, 2);
      expect(PremiumPlanKind.family.seats, 4);
    });

    test('parse round-trips the wire names and rejects the rest', () {
      for (final kind in PremiumPlanKind.values) {
        expect(PremiumPlanKindInfo.parse(kind.name), kind);
      }
      expect(PremiumPlanKindInfo.parse('dynasty'), isNull);
      expect(PremiumPlanKindInfo.parse(null), isNull);
    });
  });

  group('PremiumPricing', () {
    test('every plan has a price for every length', () {
      for (final kind in PremiumPlanKind.values) {
        for (final d in PremiumDuration.values) {
          expect(PremiumPricing.priceFor(kind, d), greaterThan(0));
        }
      }
    });

    test('a bigger plan always costs more, but less than the smaller one times its ratio', () {
      for (final d in PremiumDuration.values) {
        final solo = PremiumPricing.priceFor(PremiumPlanKind.individual, d);
        final pair = PremiumPricing.priceFor(PremiumPlanKind.couple, d);
        final family = PremiumPricing.priceFor(PremiumPlanKind.family, d);
        expect(pair, greaterThan(solo));
        expect(pair, lessThan(solo * 2));
        expect(family, greaterThan(pair));
        expect(family, lessThan(pair * 2));
      }
    });

    test('per-person price falls with every step up in plan size', () {
      for (final d in PremiumDuration.values) {
        final solo = PremiumPricing.perPersonPerMonth(PremiumPlanKind.individual, d);
        final pair = PremiumPricing.perPersonPerMonth(PremiumPlanKind.couple, d);
        final family = PremiumPricing.perPersonPerMonth(PremiumPlanKind.family, d);
        expect(pair, lessThan(solo));
        expect(family, lessThan(pair));
      }
    });

    test('family per-person figures', () {
      expect(PremiumPricing.perPersonPerMonth(PremiumPlanKind.family, PremiumDuration.month), 137);
      expect(PremiumPricing.perPersonPerMonth(PremiumPlanKind.family, PremiumDuration.year), 91);
    });

    test('the long lengths discount the family plan like the couple plan', () {
      for (final kind in [PremiumPlanKind.couple, PremiumPlanKind.family]) {
        final month = PremiumPricing.priceFor(kind, PremiumDuration.month);
        final quarter = PremiumPricing.priceFor(kind, PremiumDuration.threeMonths);
        final year = PremiumPricing.priceFor(kind, PremiumDuration.year);
        expect(quarter, lessThan(month * 3));
        expect(year, lessThan(month * 12));
        expect(year / (month * 12), closeTo(0.667, 0.01));
      }
    });
  });
}
