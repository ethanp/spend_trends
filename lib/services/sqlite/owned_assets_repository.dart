import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/owned_asset_kind.dart';
import 'package:uuid/uuid.dart';

const _log = ELogger('OwnedAssetsRepository');

class OwnedAssetsRepository(final PowerSyncDatabase _powerSync) {
  final _uuid = const Uuid();

  Future<List<OwnedAssetWithValuations>> listWithValuations() async {
    try {
      final assetRows = await _powerSync.getAll(
        'SELECT * FROM owned_assets ORDER BY name COLLATE NOCASE',
      );
      final valuationRows = await _powerSync.getAll(
        'SELECT * FROM owned_asset_valuations',
      );
      final valuationsByAssetId = <String, List<OwnedAssetValuation>>{};
      for (final row in valuationRows) {
        final valuation = _valuationFromRow(row);
        valuationsByAssetId
            .putIfAbsent(valuation.ownedAssetId, () => [])
            .add(valuation);
      }
      return [
        for (final row in assetRows)
          OwnedAssetWithValuations(
            asset: _assetFromRow(row),
            valuations: valuationsByAssetId[_idFromRow(row)] ?? const [],
          ),
      ];
    } catch (error, stackTrace) {
      _log.error('Failed to list owned assets', error, stackTrace);
      rethrow;
    }
  }

  Future<OwnedAssetWithValuations> create({
    required String name,
    required OwnedAssetKind kind,
    required int valueCents,
    required DateTime valuedOn,
    String? note,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Name is required.');
    }
    final asset = OwnedAsset(
      id: _uuid.v4(),
      name: trimmedName,
      kind: kind,
      note: _normalizedNote(note),
    );
    await _upsertAssetRow(asset);
    await appendValuation(
      ownedAssetId: asset.id,
      valueCents: valueCents,
      valuedOn: valuedOn,
    );
    final listed = await listWithValuations();
    for (final entry in listed) {
      if (entry.asset.id == asset.id) return entry;
    }
    throw StateError('Created owned asset ${asset.id} was not listed.');
  }

  Future<void> updateAsset(OwnedAsset asset) async {
    final trimmedName = asset.name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Name is required.');
    }
    await _upsertAssetRow(
      OwnedAsset(
        id: asset.id,
        name: trimmedName,
        kind: asset.kind,
        note: _normalizedNote(asset.note),
      ),
    );
  }

  Future<void> deleteAsset(String ownedAssetId) async {
    await _powerSync.execute(
      'DELETE FROM owned_asset_valuations WHERE owned_asset_id = ?',
      [ownedAssetId],
    );
    await _powerSync.execute('DELETE FROM owned_assets WHERE id = ?', [
      ownedAssetId,
    ]);
  }

  Future<void> appendValuation({
    required String ownedAssetId,
    required int valueCents,
    required DateTime valuedOn,
  }) async {
    await _powerSync.upsert('owned_asset_valuations', {
      'id': _uuid.v4(),
      'owned_asset_id': ownedAssetId,
      'value_cents': valueCents,
      'valued_on': valuedOn.startOfDay.millisecondsSinceEpoch,
    });
  }

  Future<void> updateValuation(OwnedAssetValuation valuation) async {
    await _powerSync.upsert('owned_asset_valuations', {
      'id': valuation.id,
      'owned_asset_id': valuation.ownedAssetId,
      'value_cents': valuation.valueCents,
      'valued_on': valuation.valuedOn.startOfDay.millisecondsSinceEpoch,
    });
  }

  Future<void> deleteValuation(String valuationId) async {
    final row = await _powerSync.getOptional(
      'SELECT owned_asset_id FROM owned_asset_valuations WHERE id = ?',
      [valuationId],
    );
    if (row == null) {
      throw StateError('Valuation $valuationId not found.');
    }
    final ownedAssetId = (row as Map)['owned_asset_id'] as String;
    final countRow = await _powerSync.get(
      'SELECT COUNT(*) AS n FROM owned_asset_valuations WHERE owned_asset_id = ?',
      [ownedAssetId],
    );
    final remaining = (countRow['n'] as Object?).asIntOrNull() ?? 0;
    if (remaining <= 1) {
      throw StateError('An owned asset must keep at least one valuation.');
    }
    await _powerSync.execute(
      'DELETE FROM owned_asset_valuations WHERE id = ?',
      [valuationId],
    );
  }

  Future<void> _upsertAssetRow(OwnedAsset asset) async {
    await _powerSync.upsert('owned_assets', {
      'id': asset.id,
      'name': asset.name,
      'asset_kind': asset.kind.storageValue,
      'note': asset.note,
    });
  }

  static String _idFromRow(dynamic row) {
    return ((row as Map).cast<String, Object?>())['id'] as String;
  }

  static OwnedAsset _assetFromRow(dynamic row) {
    final columns = (row as Map).cast<String, Object?>();
    return OwnedAsset(
      id: columns['id'] as String,
      name: columns['name'] as String,
      kind: OwnedAssetKind.fromStorage(columns['asset_kind'] as String),
      note: columns['note'] as String?,
    );
  }

  static OwnedAssetValuation _valuationFromRow(dynamic row) {
    final columns = (row as Map).cast<String, Object?>();
    return OwnedAssetValuation(
      id: columns['id'] as String,
      ownedAssetId: columns['owned_asset_id'] as String,
      valueCents: columns['value_cents'].asInt(),
      valuedOn: columns['valued_on'].asInt().dateTimeFromMillis.startOfDay,
    );
  }

  static String? _normalizedNote(String? note) {
    final trimmed = note?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

final ownedAssetsRepositoryProvider = FutureProvider<OwnedAssetsRepository>((
  ref,
) async {
  final database = await ref.watch(powerSyncDatabaseProvider.future);
  return OwnedAssetsRepository(database);
});
