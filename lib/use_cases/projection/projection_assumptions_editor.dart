import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/projection/projection_assumptions.dart';
import 'package:spend_trends/data/repositories/projection_settings_repository.dart';

/// Saves assumption changes (JSON-shaped keys, see
/// [ProjectionAssumptions.merged]) to the synced row, which
/// [projectionAssumptionsProvider] follows.
class ProjectionAssumptionsEditor(final Ref _ref) {
  Future<ProjectionAssumptions> apply(Map<String, dynamic> changes) async {
    final ProjectionSettingsRepository repository = await _ref.read(
      projectionSettingsRepositoryProvider.future,
    );
    final updated = (await repository.loadAssumptions()).merged(changes);
    await repository.saveAssumptions(updated);
    return updated;
  }
}

final projectionAssumptionsEditorProvider =
    Provider<ProjectionAssumptionsEditor>(ProjectionAssumptionsEditor.new);
