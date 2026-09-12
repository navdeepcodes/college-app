class TextFilterResult {
  final bool isAllowed;
  final String cleanedText;

  const TextFilterResult({
    required this.isAllowed,
    required this.cleanedText,
  });
}

class TextFilter {
  // ❌ banned words (example – extend later)
  static final List<String> _bannedWords = [
    'fuck',
    'shit',
    'bitch',
    'asshole',
    'slut',
    'whore',
    'dick',
    'pussy',
    'cunt',
    'motherfucker',
    'retard',
    'nigger',
    'chink',
    'faggot',
    'madarchod',
    'bhenchod',
    'bhosdike',
    'chutiya',
    'gaand',
    'randi',
    'loda',
    'lowda',
    'thunne',
    'nin amman',
    'sule',
    'shata',
    'cunt',
    'boobs',
    'thullu',
    'lanja',
  ];

  // ❌ banned emojis
  static final List<String> _bannedEmojis = [
    '🖕',
    '🍑',
    '🍆',
  ];

  /// Main filter method
  static TextFilterResult filter(String input) {
    final lower = input.toLowerCase();

    // 🚫 check banned words
    for (final word in _bannedWords) {
      if (lower.contains(word)) {
        return const TextFilterResult(
          isAllowed: false,
          cleanedText: '',
        );
      }
    }

    // 🚫 check banned emojis
    for (final emoji in _bannedEmojis) {
      if (input.contains(emoji)) {
        return const TextFilterResult(
          isAllowed: false,
          cleanedText: '',
        );
      }
    }

    // ✅ allowed
    return TextFilterResult(
      isAllowed: true,
      cleanedText: input,
    );
  }
}