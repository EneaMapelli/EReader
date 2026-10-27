import 'package:ereader/domain/cloud_cost_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Optional USD character budget calculator', () {
    test('converts exact cents to a conservative quota', () {
      final quote = CloudCostEstimate.fromUsdText(
        pricePerMillion: '15.00', totalBudget: '1.50',
      );
      expect(quote.pricePerMillionCents, 1500);
      expect(quote.budgetCents, 150);
      expect(quote.characterLimit, 100000);
      expect(quote.estimatedUsdForCharacters(100000), '1.5000');
    });

    test('floors fractional characters instead of increasing paid quota', () {
      final quote = CloudCostEstimate.fromUsdText(
        pricePerMillion: '3', totalBudget: '0.01',
      );
      expect(quote.characterLimit, 3333);
    });

    test('caps calculations at the actual SQLite consent limit', () {
      final quote = CloudCostEstimate.fromUsdText(
        pricePerMillion: '0.01', totalBudget: '100',
      );
      expect(quote.characterLimit, 10000000);
    });

    test('tiny budget can intentionally yield zero allowed characters', () {
      final quote = CloudCostEstimate.fromUsdText(
        pricePerMillion: '999999.99', totalBudget: '0.01',
      );
      expect(quote.characterLimit, 0);
    });

    test('refuses implicit, malformed, negative or zero prices and budgets',
        () {
      for (final invalid in [
        '', '0', '0.00', '-1', '+1', '1,50', '1.234', '1e2',
        r'$1.50', '1000000', '01.20', 'NaN', 'Infinity',
      ]) {
        expect(
          () => CloudCostEstimate.fromUsdText(
            pricePerMillion: invalid, totalBudget: '1',
          ),
          throwsFormatException,
          reason: 'Invalid unit price: $invalid',
        );
        expect(
          () => CloudCostEstimate.fromUsdText(
            pricePerMillion: '1', totalBudget: invalid,
          ),
          throwsFormatException,
          reason: 'Invalid book budget: $invalid',
        );
      }
    });

    test('whitespace and fractional cents are parsed predictably', () {
      final quote = CloudCostEstimate.fromUsdText(
        pricePerMillion: ' 0.05 ', totalBudget: '0.10',
      );
      expect(quote.pricePerMillionCents, 5);
      expect(quote.budgetCents, 10);
      expect(quote.characterLimit, 2000000);
      expect(() => quote.estimatedUsdForCharacters(-1), throwsRangeError);
    });
  });
}
