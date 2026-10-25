/// Explicit opt-in to sending *selected book excerpts* and cast names for
/// analysis. Completely independent from narration consent and its quota.
/// Input-character limits are NOT monetary limits or token billing estimates.
class LlmAnalysisConsent {
  const LlmAnalysisConsent({
    required this.bookId,
    required this.allowed,
    required this.maxInputCharacters,
    required this.usedInputCharacters,
    this.approvedAt,
  });

  final String bookId;
  final bool allowed;
  final int maxInputCharacters;
  final int usedInputCharacters;
  final DateTime? approvedAt;

  int get remainingInputCharacters =>
      (maxInputCharacters - usedInputCharacters)
          .clamp(0, maxInputCharacters).toInt();

  void validate() {
    if (bookId.isEmpty || maxInputCharacters < 0 ||
        maxInputCharacters > 10000000 || usedInputCharacters < 0 ||
        usedInputCharacters > maxInputCharacters) {
      throw const FormatException('Invalid character-analysis permission');
    }
  }
}

class LlmAnalysisDenied implements Exception {
  const LlmAnalysisDenied(this.reason);
  final String reason;

  @override
  String toString() => 'Dialogue analysis unavailable: $reason';
}

abstract interface class LlmAnalysisAccess {
  LlmAnalysisConsent getLlmAnalysisConsent(String bookId);
  Future<void> reserveLlmAnalysisInput(String bookId, int characters);
}
