import 'dart:convert';

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
      'details_json': switch (_detailsOf(event)) {
        null => null,
        final details => jsonEncode(details),
      },
    });
  }

  Future<void> delete(String eventId) async {
    await _powerSync.execute('DELETE FROM life_events WHERE id = ?', [eventId]);
  }

  static String? _normalizedNote(String? note) {
    final trimmed = note?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// The kind's own fields, stored as `details_json`; null for kinds with none.
  static Map<String, Object?>? _detailsOf(LifeEvent event) => switch (event) {
    Milestone() || ChildBirth() => null,
    Job() => {
      'takeHomeSalaryAnnual': event.takeHomeSalaryAnnual,
      'takeHomeBonusAnnual': event.takeHomeBonusAnnual,
    },
    HomeOwnership() => {
      'price': event.price,
      'downPayment': event.downPayment,
      'mortgage': switch (event.mortgage) {
        null => null,
        final mortgage => {
          'ratePercent': mortgage.ratePercent,
          'years': mortgage.years,
          'hasEscrow': mortgage.hasEscrow,
        },
      },
      'insuranceAnnual': event.insuranceAnnual,
      'hoaAnnual': event.hoaAnnual,
      'maintenancePercent': event.maintenancePercent,
      'propertyTaxPercent': event.propertyTaxPercent,
    },
  };

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
    final kind = LifeEventKind.values.asNameMap()[columns['kind']];
    return switch (kind ?? LifeEventKind.milestone) {
      LifeEventKind.milestone => Milestone(
        id: id,
        title: title,
        startedOn: startedOn,
        endedOn: endedOn,
        note: note,
      ),
      LifeEventKind.job => Job(
        id: id,
        title: title,
        startedOn: startedOn,
        endedOn: endedOn,
        note: note,
        takeHomeSalaryAnnual: details['takeHomeSalaryAnnual'] as int? ?? 0,
        takeHomeBonusAnnual: details['takeHomeBonusAnnual'] as int? ?? 0,
      ),
      LifeEventKind.home => HomeOwnership(
        id: id,
        title: title,
        startedOn: startedOn,
        endedOn: endedOn,
        note: note,
        price: details['price'] as int? ?? 0,
        downPayment: details['downPayment'] as int? ?? 0,
        mortgage: switch (details['mortgage']) {
          final Map<String, dynamic> mortgage => Mortgage(
            ratePercent: (mortgage['ratePercent'] as num).toDouble(),
            years: mortgage['years'] as int,
            hasEscrow: mortgage['hasEscrow'] as bool,
          ),
          _ => null,
        },
        insuranceAnnual: details['insuranceAnnual'] as int? ?? 0,
        hoaAnnual: details['hoaAnnual'] as int? ?? 0,
        maintenancePercent:
            (details['maintenancePercent'] as num?)?.toDouble() ?? 0,
        propertyTaxPercent:
            (details['propertyTaxPercent'] as num?)?.toDouble() ?? 0,
      ),
      LifeEventKind.childBirth => ChildBirth(
        id: id,
        title: title,
        startedOn: startedOn,
        endedOn: endedOn,
        note: note,
      ),
    };
  }
}

final lifeEventsRepositoryProvider = FutureProvider<LifeEventsRepository>((
  ref,
) async {
  final database = await ref.watch(powerSyncDatabaseProvider.future);
  return LifeEventsRepository(database);
});
