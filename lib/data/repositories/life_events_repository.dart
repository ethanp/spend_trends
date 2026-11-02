import 'dart:convert';

import 'package:spend_trends/domain/projection/life_event.dart';
import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';
import 'package:spend_trends/data/sync/spend_data_changed.dart';

const _log = ELogger('LifeEventsRepository');

class LifeEventsRepository(final PowerSyncDatabase _powerSync) {
  final _uuid = const Uuid();

  Future<List<LifeEvent>> listNewestFirst() async {
    try {
      final rows = await _powerSync.getAll('''
        SELECT * FROM life_events
        ORDER BY started_on DESC, title COLLATE NOCASE
        ''');
      return rows.map(_fromRow).toList();
    } catch (error, stackTrace) {
      _log.error('Failed to list life events', error, stackTrace);
      rethrow;
    }
  }

  /// A fresh id for an event about to be saved with [upsert].
  String newId() => _uuid.v4();

  Future<void> upsert(LifeEvent event) async {
    final trimmedTitle = event.title.trim();
    if (trimmedTitle.isEmpty) {
      throw ArgumentError('Title is required.');
    }
    final startedOn = event.startedOn.startOfDay;
    final endedOn = event.endedOn?.startOfDay;
    if (endedOn != null && endedOn.isBefore(startedOn)) {
      throw ArgumentError('End date cannot be before start date.');
    }
    await _powerSync.upsert('life_events', {
      'id': event.id,
      'title': trimmedTitle,
      'started_on': startedOn.millisecondsSinceEpoch,
      'ended_on': endedOn?.millisecondsSinceEpoch,
      'note': _normalizedNote(event.note),
      'kind': event.kind.name,
      'details_json': switch (event.details) {
        null => null,
        final details => jsonEncode(details),
      },
    });
  }

  Future<void> delete(String eventId) async {
    await _powerSync.execute('DELETE FROM life_events WHERE id = ?', [eventId]);
  }

  static String? _normalizedNote(String? note) {
    final trimmed = note.trimmedOrEmpty;
    return trimmed.isEmpty ? null : trimmed;
  }

  static LifeEvent _fromRow(dynamic row) {
    final columns = (row as Map).cast<String, Object?>();
    final id = columns['id'] as String;
    final startedOnMillis = columns['started_on'].asIntOrNull();
    if (startedOnMillis == null) {
      throw StateError(
        'Life event $id is missing started_on. '
        'Restart the app to finish the local schema migration.',
      );
    }
    final startedOn = startedOnMillis.dateTimeFromMillis.startOfDay;
    final endedOn = columns['ended_on']
        .asIntOrNull()
        .dateTimeFromMillis
        ?.startOfDay;
    final title = columns['title'] as String;
    final note = columns['note'] as String?;
    final details = switch (columns['details_json']) {
      final String json => jsonDecode(json) as Map<String, dynamic>,
      _ => const <String, dynamic>{},
    };
    return LifeEvent.fromStorage(
      id: id,
      kind:
          LifeEventKind.values.asNameMap()[columns['kind']] ??
          LifeEventKind.milestone,
      title: title,
      startedOn: startedOn,
      endedOn: endedOn,
      note: note,
      details: details,
    );
  }
}

final lifeEventsRepositoryProvider = FutureProvider<LifeEventsRepository>((
  ref,
) async {
  final database = await ref.watch(powerSyncDatabaseProvider.future);
  return LifeEventsRepository(database);
});

final lifeEventsProvider = FutureProvider<List<LifeEvent>>((ref) async {
  ref.watch(spendDataChangedProvider);
  final repository = await ref.watch(lifeEventsRepositoryProvider.future);
  return repository.listNewestFirst();
});
