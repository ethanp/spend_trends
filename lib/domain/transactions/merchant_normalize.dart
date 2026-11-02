/// Merchant name normalization for spend_trends matching / display.
String normalizeMerchant(String rawDescription) {
  final collapsed = rawDescription.trim().replaceAll(RegExp(r'\s+'), ' ');
  return collapsed.toUpperCase();
}
