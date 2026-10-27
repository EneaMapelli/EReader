/// A local, optional USD-to-character calculator. This is never a
/// substitute for the provider's invoice, current pricing or account limits.
///
/// No price is bundled or fetched; nothing is persisted. EReader only stores
/// a *character* limit after a separate user confirmation. The existing
/// CloudSpeechAccess.reserveCharacters remains the source of truth.
///
/// Both USD inputs accept exact dollars/cents to avoid floating-point
/// rounding when computing a quota. Monetary values are bounded so the
/// integer calculations remain safe on Dart VM and JS implementations.
class CloudCostEstimate {
  const CloudCostEstimate._(this.pricePerMillionCents, this.budgetCents);

  final int pricePerMillionCents;
  final int budgetCents;

  /// Amounts must be greater than zero and have at most two decimal places.
  /// No locale-dependent commas, exponent forms, negatives or implicit rates.
  factory CloudCostEstimate.fromUsdText({
    required String pricePerMillion,
    required String totalBudget,
  }) {
    return CloudCostEstimate._(
      _usdCents(pricePerMillion),
      _usdCents(totalBudget),
    );
  }

  static final RegExp _amountPattern =
      RegExp(r'^(0|[1-9][0-9]{0,5})(?:\.([0-9]{1,2}))?$');

  static int _usdCents(String raw) {
    final match = _amountPattern.firstMatch(raw.trim());
    if (match == null) {
      throw const FormatException(
        'Use a positive USD amount with at most 2 decimal places, '
        'without commas or currency symbols (e.g. 1.50).',
      );
    }
    final whole = int.parse(match.group(1)!);
    final cents = int.parse((match.group(2) ?? '').padRight(2, '0'));
    final amount = whole * 100 + cents;
    if (amount <= 0) {
      throw const FormatException('USD amount must be positive.');
    }
    return amount;
  }

  /// Floor the derived character quota so the estimate never rounds up.
  /// This is capped by the database's existing 10-million-character limit.
  int get characterLimit {
    final characters = (budgetCents * 1000000) ~/ pricePerMillionCents;
    return characters.clamp(0, 10000000).toInt();
  }

  /// Estimated, NOT billed USD for already reserved or proposed characters.
  /// The text is formatted to four decimals to show small usage estimates.
  String estimatedUsdForCharacters(int characters) {
    if (characters < 0 || characters > 10000000) {
      throw RangeError.range(characters, 0, 10000000, 'characters');
    }
    final dollars = characters * pricePerMillionCents / 100000000;
    return dollars.toStringAsFixed(4);
  }
}
