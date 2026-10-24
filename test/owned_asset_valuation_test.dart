import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/owned_asset_kind.dart';

void main() {
  const home = OwnedAsset(id: 'home', name: 'Home', kind: OwnedAssetKind.home);

  OwnedAssetWithValuations assetWith(List<OwnedAssetValuation> valuations) {
    return OwnedAssetWithValuations(asset: home, valuations: valuations);
  }

  test('current value is the newest valued-on snapshot', () {
    final owned = assetWith([
      OwnedAssetValuation(
        id: 'v1',
        ownedAssetId: 'home',
        valueCents: 20000000,
        valuedOn: DateTime(2022, 1, 1),
      ),
      OwnedAssetValuation(
        id: 'v2',
        ownedAssetId: 'home',
        valueCents: 35000000,
        valuedOn: DateTime(2024, 6, 1),
      ),
    ]);

    expect(owned.currentValueCents, 35000000);
    expect(owned.latestValuedOn, DateTime(2024, 6, 1));
    expect(owned.firstValuedOn, DateTime(2022, 1, 1));
  });

  test('valueCentsOn is 0 before the first snapshot, then steps', () {
    final owned = assetWith([
      OwnedAssetValuation(
        id: 'v1',
        ownedAssetId: 'home',
        valueCents: 20000000,
        valuedOn: DateTime(2024, 1, 2),
      ),
      OwnedAssetValuation(
        id: 'v2',
        ownedAssetId: 'home',
        valueCents: 25000000,
        valuedOn: DateTime(2024, 1, 4),
      ),
    ]);

    expect(owned.valueCentsOn(DateTime(2024, 1, 1)), 0);
    expect(owned.valueCentsOn(DateTime(2024, 1, 2)), 20000000);
    expect(owned.valueCentsOn(DateTime(2024, 1, 3)), 20000000);
    expect(owned.valueCentsOn(DateTime(2024, 1, 4)), 25000000);
    expect(owned.valueCentsOn(DateTime(2024, 1, 5)), 25000000);
  });

  test('dailyCents walks chart dates as a step series', () {
    final owned = assetWith([
      OwnedAssetValuation(
        id: 'v1',
        ownedAssetId: 'home',
        valueCents: 10000000,
        valuedOn: DateTime(2024, 1, 2),
      ),
      OwnedAssetValuation(
        id: 'v2',
        ownedAssetId: 'home',
        valueCents: 12000000,
        valuedOn: DateTime(2024, 1, 4),
      ),
    ]);
    final chartDates = [
      DateTime(2024, 1, 1),
      DateTime(2024, 1, 2),
      DateTime(2024, 1, 3),
      DateTime(2024, 1, 4),
    ];

    expect(owned.dailyCents(chartDates), [
      0.0,
      10000000.0,
      10000000.0,
      12000000.0,
    ]);
  });

  test('value is 0 on and after the sold date', () {
    final owned = OwnedAssetWithValuations(
      asset: OwnedAsset(
        id: 'home',
        name: 'Home',
        kind: OwnedAssetKind.home,
        soldOn: DateTime(2024, 1, 4),
      ),
      valuations: [
        OwnedAssetValuation(
          id: 'v1',
          ownedAssetId: 'home',
          valueCents: 20000000,
          valuedOn: DateTime(2024, 1, 2),
        ),
        OwnedAssetValuation(
          id: 'v2',
          ownedAssetId: 'home',
          valueCents: 25000000,
          valuedOn: DateTime(2024, 1, 3),
        ),
      ],
    );

    expect(owned.valueCentsOn(DateTime(2024, 1, 3)), 25000000);
    expect(owned.valueCentsOn(DateTime(2024, 1, 4)), 0);
    expect(owned.valueCentsOn(DateTime(2024, 1, 5)), 0);
    expect(owned.currentValueCents, 0);
    expect(owned.latestValueCents, 25000000);
    expect(owned.dailyCents([DateTime(2024, 1, 3), DateTime(2024, 1, 4)]), [
      25000000.0,
      0.0,
    ]);
  });

  test('a future sold date still counts the latest value today', () {
    final owned = OwnedAssetWithValuations(
      asset: OwnedAsset(
        id: 'home',
        name: 'Home',
        kind: OwnedAssetKind.home,
        soldOn: DateTime(2099, 1, 1),
      ),
      valuations: [
        OwnedAssetValuation(
          id: 'v1',
          ownedAssetId: 'home',
          valueCents: 10000000,
          valuedOn: DateTime(2024, 1, 2),
        ),
      ],
    );

    expect(owned.asset.isSold, isFalse);
    expect(owned.currentValueCents, 10000000);
    expect(owned.valueCentsOn(DateTime(2098, 12, 31)), 10000000);
    expect(owned.valueCentsOn(DateTime(2099, 1, 1)), 0);
  });
}
