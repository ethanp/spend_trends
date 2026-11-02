class const CategorySuggestPrompt() {
  String buildSystemPrompt() => '''
You categorize bank transactions for a personal budget app.
Return JSON only: {"suggestions":[{"merchant":"...","category":"..."}]}.
Prefer an existing category from the provided list when it clearly fits.
If none fit well, propose a short new category name (Title Case, 1–3 words) that would be useful going forward.
Never use "Other", "Misc", "Miscellaneous", "Uncategorized", or other vague catch-alls.
Omit a merchant only if you truly cannot propose a meaningful category.
''';

  String buildUserPrompt({
    required List<String> categoryNames,
    required List<String> merchants,
  }) {
    return '''
Existing categories:
${categoryNames.map((name) => '- $name').join('\n')}

Merchants to categorize:
${merchants.map((merchant) => '- $merchant').join('\n')}
''';
  }
}
