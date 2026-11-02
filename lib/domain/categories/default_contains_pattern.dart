/// Default "description contains" pattern for a new categorization rule.
///
/// Uses the full merchant (or raw description) lowercased. Specific is safer
/// than a single vague token — the user can shorten in the sheet.
String defaultContainsPattern({
  required String normalizedMerchant,
  required String rawDescription,
}) {
  final source = normalizedMerchant.trim().isNotEmpty
      ? normalizedMerchant
      : rawDescription;
  return source.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}
