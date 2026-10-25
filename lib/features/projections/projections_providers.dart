import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/life_event.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/projection/assumption_sweep.dart';
import 'package:spend_trends/domain/projection/life_plan.dart';
import 'package:spend_trends/domain/projection/projection_assumptions.dart';
import 'package:spend_trends/domain/projection/projection_starting_point.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/activity/transactions_list_provider.dart';
import 'package:spend_trends/features/banks/banks_providers.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/features/life_events/life_events_providers.dart';
import 'package:spend_trends/features/owned_assets/owned_assets_providers.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/projection_settings_repository.dart';

final projectionAssumptionsProvider = FutureProvider<ProjectionAssumptions>((
  ref,
) async {
  ref.watch(spendDataChangedProvider);
  final ProjectionSettingsRepository repository = await ref.watch(
    projectionSettingsRepositoryProvider.future,
  );
  return repository.loadAssumptions();
});

/// Live balances, homes, and last year's flows, as of today. Scans every
/// transaction, so it is kept apart from the assumptions: saving one does
/// not rebuild it.
final projectionStartingPointProvider =
    FutureProvider<ProjectionStartingPoint>((ref) async {
      final Map<String, Account> accounts = await ref.watch(
    accountsMapProvider.future,
  );
  final List<OwnedAssetWithValuations> ownedAssets = await ref.watch(
    ownedAssetsListProvider.future,
  );
  final List<BankTransaction> transactions = await ref.watch(
    transactionsListProvider.future,
  );
  final List<SpendCategory> categories = await ref.watch(
    categoriesListProvider.future,
  );
      return ProjectionStartingPoint.from(
        today: DateTime.now(),
        accounts: accounts.values.toList(),
        ownedAssets: ownedAssets,
        transactions: transactions,
        categories: categories,
      );
    });

/// The projection from the live starting point, life events, and the saved
/// assumptions.
final retirementProjectionProvider = FutureProvider<RetirementProjection>((
  ref,
) async {
  final ProjectionAssumptions assumptions = await ref.watch(
    projectionAssumptionsProvider.future,
  );
  final ProjectionStartingPoint start = await ref.watch(
    projectionStartingPointProvider.future,
  );
  final List<LifeEvent> lifeEvents = await ref.watch(lifeEventsProvider.future);
  return RetirementProjection(
    start: start,
    lifePlan: LifePlan(lifeEvents),
    assumptions: assumptions,
  );
});

/// Assumption changes being dragged but not yet saved (JSON-shaped keys).
final projectionAssumptionDraftsProvider =
    NotifierProvider<ProjectionAssumptionDrafts, Map<String, Object?>>(
      ProjectionAssumptionDrafts.new,
    );

class ProjectionAssumptionDrafts() extends Notifier<Map<String, Object?>> {
  @override
  Map<String, Object?> build() => const {};

  void drag(String assumptionKey, Object? value) =>
      state = {...state, assumptionKey: value};

  /// Saves the released value, then drops the draft once the saved
  /// projection carries it, so the slider never snaps back.
  Future<void> release(String assumptionKey, Object? value) async {
    await ref.read(projectionAssumptionsEditorProvider).apply({
      assumptionKey: value,
    });
    await ref.read(retirementProjectionProvider.future);
    state = {...state}..remove(assumptionKey);
  }
}

/// The saved projection re-run with any assumption being dragged, so every
/// card follows the slider. Once loaded it never goes back to loading: a
/// reload after a save keeps showing the last projection until the new
/// one is ready.
final draftedRetirementProjectionProvider =
    Provider<AsyncValue<RetirementProjection>>((ref) {
      final Map<String, Object?> drafts = ref.watch(
        projectionAssumptionDraftsProvider,
      );
      final AsyncValue<RetirementProjection> savedAsync = ref.watch(
        retirementProjectionProvider,
      );
      final RetirementProjection? saved = savedAsync.value;
      if (saved == null) return savedAsync;
      if (drafts.isEmpty) return AsyncData(saved);
      return AsyncData(
        RetirementProjection(
          start: saved.start,
          lifePlan: saved.lifePlan,
          assumptions: saved.assumptions.merged(drafts),
        ),
      );
    });

/// A slider's landscape around the saved assumptions. It stays put while
/// that slider is dragged, since the other assumptions hold still. Each
/// sweep re-runs dozens of projections, so it runs on another isolate to
/// keep frames smooth.
final assumptionSweepProvider =
    FutureProvider.family<List<SweepPoint>, AssumptionSweepRange>((
      ref,
      range,
    ) async {
      final RetirementProjection saved = await ref.watch(
        retirementProjectionProvider.future,
      );
      return Isolate.run(
        () => AssumptionSweep(
          projection: saved,
          assumptionKey: range.assumptionKey,
          min: range.min,
          max: range.max,
          step: range.step,
          outcomeKind: range.outcomeKind,
        ).points,
      );
    });

/// Which assumption a sweep moves, across what range, and what it reads.
class const AssumptionSweepRange({
  required final String assumptionKey,
  required final double min,
  required final double max,
  required final double step,
  required final SweepOutcomeKind outcomeKind,
}) {
  @override
  bool operator ==(Object other) =>
      other is AssumptionSweepRange &&
      other.assumptionKey == assumptionKey &&
      other.min == min &&
      other.max == max &&
      other.step == step &&
      other.outcomeKind == outcomeKind;

  @override
  int get hashCode => Object.hash(assumptionKey, min, max, step, outcomeKind);
}

/// Saves assumption changes (JSON-shaped keys, see
/// [ProjectionAssumptions.merged]) to the synced row and refreshes screens.
class ProjectionAssumptionsEditor(final Ref _ref) {
  Future<ProjectionAssumptions> apply(Map<String, dynamic> changes) async {
    final ProjectionSettingsRepository repository = await _ref.read(
      projectionSettingsRepositoryProvider.future,
    );
    final updated = (await repository.loadAssumptions()).merged(changes);
    await repository.saveAssumptions(updated);
    // Only the projection reads assumptions; reloading every transaction
    // and account for a slider release would be wasted work.
    _ref.invalidate(projectionAssumptionsProvider);
    return updated;
  }
}

final projectionAssumptionsEditorProvider =
    Provider<ProjectionAssumptionsEditor>(ProjectionAssumptionsEditor.new);
