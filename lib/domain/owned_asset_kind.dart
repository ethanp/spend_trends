import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

/// Kind of a manually tracked owned asset (home, vehicle, other).
enum OwnedAssetKind({
  required final Color lineColor,
}) {
  home(lineColor: Color(0xFFF4A261)),
  vehicle(lineColor: Color(0xFFE76F51)),
  other(lineColor: Color(0xFFE9A825));

  String get legendLabel => nameAsCapitalizedWords;

  String get storageValue => name;

  static OwnedAssetKind fromStorage(String value) {
    return tryFromStorage(value) ?? OwnedAssetKind.other;
  }

  static OwnedAssetKind? tryFromStorage(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    for (final kind in OwnedAssetKind.values) {
      if (kind.name == trimmed) return kind;
    }
    return null;
  }
}
