import 'package:spend_trends/domain/stay_chain.dart';
import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';

/// CRUD for a single stay-chain table (`housing_stays` or `job_stays`).
class ChainStaysRepository(
  final PowerSyncDatabase _powerSync, {
  required final String tableName,
}) {
  final _uuid = const Uuid();

  Future<StayChain> loadChain() async {
    final stays = await listOldestFirst();
    return StayChain(stays);
  }

  Future<List<ChainStay>> listOldestFirst() async {
    final rows = await _powerSync.getAll('''
      SELECT * FROM $tableName
      ORDER BY started_on ASC, label COLLATE NOCASE
      ''');
    return rows.map(_fromRow).toList();
  }

  Future<ChainStay> create({
    required String label,
    required DateTime startedOn,
    String? note,
  }) async {
    final stay = ChainStay(
      id: _uuid.v4(),
      label: label.trim(),
      startedOn: startedOn.startOfDay,
      note: _normalizedNote(note),
    );
    await upsert(stay);
    return stay;
  }

  Future<void> upsert(ChainStay stay) async {
    final trimmedLabel = stay.label.trim();
    if (trimmedLabel.isEmpty) {
      throw ArgumentError('Label is required.');
    }
    await _powerSync.upsert(tableName, {
      'id': stay.id,
      'label': trimmedLabel,
      'started_on': stay.startedOn.startOfDay.millisecondsSinceEpoch,
      'note': _normalizedNote(stay.note),
    });
  }

  Future<void> delete(String stayId) async {
    await _powerSync.execute('DELETE FROM $tableName WHERE id = ?', [stayId]);
  }

  static String? _normalizedNote(String? note) {
    final trimmed = note?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static ChainStay _fromRow(dynamic row) {
    final columns = (row as Map).cast<String, Object?>();
    final startedOnMillis = columns['started_on'].asIntOrNull();
    if (startedOnMillis == null) {
      throw StateError('Stay ${columns['id']} is missing started_on.');
    }
    return ChainStay(
      id: columns['id'] as String,
      label: columns['label'] as String,
      startedOn: startedOnMillis.dateTimeFromMillis.startOfDay,
      note: columns['note'] as String?,
    );
  }
}

final housingStaysRepositoryProvider = FutureProvider<ChainStaysRepository>((
  ref,
) async {
  final database = await ref.watch(powerSyncDatabaseProvider.future);
  return ChainStaysRepository(database, tableName: 'housing_stays');
});

final jobStaysRepositoryProvider = FutureProvider<ChainStaysRepository>((
  ref,
) async {
  final database = await ref.watch(powerSyncDatabaseProvider.future);
  return ChainStaysRepository(database, tableName: 'job_stays');
});
