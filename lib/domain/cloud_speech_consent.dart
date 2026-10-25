/// Cloud speech is opt-in separately for EACH book and provider.
/// Budget is in characters SENT (including failed requests), not money:
/// pricing varies across providers and models and must never be invented.
class CloudSpeechConsent {
  const CloudSpeechConsent({
    required this.bookId,
    required this.providerId,
    required this.allowed,
    required this.maxCharacters,
    required this.usedCharacters,
    this.approvedAt,
  });

  final String bookId;
  final String providerId;
  final bool allowed;
  final int maxCharacters;
  final int usedCharacters;
  final DateTime? approvedAt;

  int get remainingCharacters =>
      (maxCharacters - usedCharacters).clamp(0, maxCharacters).toInt();

  void validate() {
    if (bookId.isEmpty || providerId.isEmpty ||
        maxCharacters < 0 || maxCharacters > 10000000 ||
        usedCharacters < 0 || usedCharacters > maxCharacters) {
      throw const FormatException('Invalid cloud narration consent');
    }
  }
}

/// A hard local guard, checked BEFORE any request.
abstract interface class CloudSpeechAccess {
  CloudSpeechConsent getConsent(String bookId, String providerId);
  Future<void> reserveCharacters(
      String bookId, String providerId, int characters);
}

class CloudSpeechBlocked implements Exception {
  const CloudSpeechBlocked(this.reason);
  final String reason;

  @override
  String toString() => 'Cloud speech blocked: $reason';
}
