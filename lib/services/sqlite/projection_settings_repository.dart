import 'dart:convert';

import 'package:ethan_sync/ethan_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:spend_trends/domain/projection/projection_assumptions.dart';

/// The single synced row of retirement-projection assumptions.
class ProjectionSettingsRepository(final PowerSyncDatabase _powerSync) {
  /// Saved assumptions, or the defaults before anything is saved.
  Future<ProjectionAssumptions> loadAssumptions() async {
    final row = await _powerSync.getOptional(
      'SELECT settings_json FROM projection_settings WHERE id = ?',
      [ProjectionAssumptions.settingsId],
    );
    if (row == null) return const ProjectionAssumptions();
    return ProjectionAssumptions.fromJson(
      jsonDecode(row['settings_json'] as String) as Map<String, dynamic>,
    );
  }

  Future<void> saveAssumptions(ProjectionAssumptions assumptions) async {
    await _powerSync.upsert('projection_settings', {
      'id': ProjectionAssumptions.settingsId,
      'settings_json': jsonEncode(assumptions.toJson()),
    });
  }
}

final projectionSettingsRepositoryProvider =
    FutureProvider<ProjectionSettingsRepository>((ref) async {
      final database = await ref.watch(powerSyncDatabaseProvider.future);
      return ProjectionSettingsRepository(database);
    });
