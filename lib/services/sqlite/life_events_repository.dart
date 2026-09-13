import 'package:spend_trends/domain/life_event.dart';
import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';

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

  Future<LifeEvent> create({
    required String title,
    required DateTime startedOn,
    DateTime? endedOn,
    String? note,
  }) async {
    final event = LifeEvent(
      id: _uuid.v4(),
      title: title.trim(),
      startedOn: startedOn.startOfDay,
      endedOn: endedOn?.startOfDay,
      note: _normalizedNote(note),
    );
    await upsert(event);
    return event;
  }

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
    });
  }

  Future<void> delete(String eventId) async {
    await _powerSync.execute('DELETE FROM life_events WHERE id = ?', [eventId]);
  }

  static String? _normalizedNote(String? note) {
    final trimmed = note?.trim() ?? '';
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
    return LifeEvent(
      id: id,
      title: columns['title'] as String,
      startedOn: startedOnMillis.dateTimeFromMillis.startOfDay,
      endedOn: columns['ended_on'].asIntOrNull().dateTimeFromMillis?.startOfDay,
      note: columns['note'] as String?,
    );
  }
}

final lifeEventsRepositoryProvider = FutureProvider<LifeEventsRepository>((
  ref,
) async {
  final database = await ref.watch(powerSyncDatabaseProvider.future);
  return LifeEventsRepository(database);
});
