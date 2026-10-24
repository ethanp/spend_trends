import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/owned_asset_kind.dart';

class const OwnedAsset({
  required final String id,
  required final String name,
  required final OwnedAssetKind kind,
  final String? note,
  final DateTime? soldOn,
}) {
  /// True when [soldOn] is on or before [day] (you no longer hold the asset).
  bool isSoldAsOf(DateTime day) {
    final soldOn = this.soldOn;
    if (soldOn == null) return false;
    return !soldOn.startOfDay.isAfter(day.startOfDay);
  }

  bool get isSold => isSoldAsOf(DateTime.now());

  OwnedAsset copyWith({
    String? id,
    String? name,
    OwnedAssetKind? kind,
    String? note,
    bool clearNote = false,
    DateTime? soldOn,
    bool clearSoldOn = false,
  }) {
    return OwnedAsset(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      note: clearNote ? null : (note ?? this.note),
      soldOn: clearSoldOn ? null : (soldOn ?? this.soldOn),
    );
  }
}

class const OwnedAssetValuation({
  required final String id,
  required final String ownedAssetId,
  required final int valueCents,
  required final DateTime valuedOn,
});

/// An owned asset plus its valuation snapshots, newest [valuedOn] first.
class OwnedAssetWithValuations({
  required final OwnedAsset asset,
  required List<OwnedAssetValuation> valuations,
}) {
  final List<OwnedAssetValuation> valuations = _newestFirst(valuations);

  /// Newest snapshot, ignoring [OwnedAsset.soldOn].
  int get latestValueCents {
    if (valuations.isEmpty) return 0;
    return valuations.first.valueCents;
  }

  DateTime? get latestValuedOn {
    if (valuations.isEmpty) return null;
    return valuations.first.valuedOn;
  }

  /// Today's contribution to net worth: 0 once the asset is sold.
  int get currentValueCents {
    if (asset.isSold) return 0;
    return latestValueCents;
  }

  DateTime? get firstValuedOn {
    if (valuations.isEmpty) return null;
    return valuations.last.valuedOn;
  }

  /// Latest snapshot on or before [day]; 0 before the first valuation and on or
  /// after [OwnedAsset.soldOn].
  int valueCentsOn(DateTime day) {
    final target = day.startOfDay;
    if (asset.isSoldAsOf(target)) return 0;
    for (final valuation in valuations) {
      if (!valuation.valuedOn.startOfDay.isAfter(target)) {
        return valuation.valueCents;
      }
    }
    return 0;
  }

  List<double> dailyCents(List<DateTime> chartDates) {
    return [for (final day in chartDates) valueCentsOn(day).toDouble()];
  }

  static List<OwnedAssetValuation> _newestFirst(
    List<OwnedAssetValuation> valuations,
  ) {
    final sorted = [...valuations];
    sorted.sort((left, right) {
      final byDate = right.valuedOn.compareTo(left.valuedOn);
      if (byDate != 0) return byDate;
      return right.id.compareTo(left.id);
    });
    return sorted;
  }
}
