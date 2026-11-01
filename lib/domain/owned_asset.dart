import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/owned_asset_kind.dart';

class const OwnedAsset({
  required final String id,
  required final String name,
  required final OwnedAssetKind kind,
  final String? note,
  final CalendarDay? soldOn,
}) {
  /// True when [soldOn] is on or before [day] (you no longer hold the asset).
  bool isSoldAsOf(CalendarDay day) {
    final soldOn = this.soldOn;
    if (soldOn == null) return false;
    return !soldOn.isAfter(day);
  }

  bool get isSold => isSoldAsOf(CalendarDay.today());

  OwnedAsset copyWith({
    String? id,
    String? name,
    OwnedAssetKind? kind,
    String? note,
    bool clearNote = false,
    CalendarDay? soldOn,
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
  required final CalendarDay valuedOn,
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

  CalendarDay? get latestValuedOn {
    if (valuations.isEmpty) return null;
    return valuations.first.valuedOn;
  }

  /// Today's contribution to net worth: 0 once the asset is sold.
  int get currentValueCents {
    if (asset.isSold) return 0;
    return latestValueCents;
  }

  CalendarDay? get firstValuedOn {
    if (valuations.isEmpty) return null;
    return valuations.last.valuedOn;
  }

  /// Latest snapshot on or before [day]; 0 before the first valuation and on or
  /// after [OwnedAsset.soldOn].
  int valueCentsOn(CalendarDay day) {
    if (asset.isSoldAsOf(day)) return 0;
    for (final valuation in valuations) {
      if (!valuation.valuedOn.isAfter(day)) return valuation.valueCents;
    }
    return 0;
  }

  /// [valueCentsOn] for each of [chartDays] (ascending) in one pass over the
  /// valuations.
  List<double> dailyCents(List<CalendarDay> chartDays) {
    final oldestFirst = valuations.reversed.toList(growable: false);
    final CalendarDay? soldOn = asset.soldOn;
    var nextValuationIndex = 0;
    var latestValueCents = 0;
    final dailyCents = <double>[];
    for (final day in chartDays) {
      while (nextValuationIndex < oldestFirst.length &&
          !oldestFirst[nextValuationIndex].valuedOn.isAfter(day)) {
        latestValueCents = oldestFirst[nextValuationIndex].valueCents;
        nextValuationIndex++;
      }
      final bool sold = soldOn != null && !soldOn.isAfter(day);
      dailyCents.add(sold ? 0 : latestValueCents.toDouble());
    }
    return dailyCents;
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
