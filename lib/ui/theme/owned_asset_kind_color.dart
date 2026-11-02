import 'package:flutter/material.dart';
import 'package:spend_trends/domain/accounts/owned_asset_kind.dart';

extension OwnedAssetKindColor on OwnedAssetKind {
  Color get lineColor => switch (this) {
    OwnedAssetKind.home => const Color(0xFFF4A261),
    OwnedAssetKind.vehicle => const Color(0xFFE76F51),
    OwnedAssetKind.other => const Color(0xFFE9A825),
  };
}
