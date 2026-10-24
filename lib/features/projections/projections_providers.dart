import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/domain/projection/projection_assumptions.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/activity/transactions_list_provider.dart';
import 'package:spend_trends/features/banks/banks_providers.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
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

/// The projection from live balances, last year's flows, and the saved
/// assumptions, as of today.
final retirementProjectionProvider = FutureProvider<RetirementProjection>((
  ref,
) async {
  final ProjectionAssumptions assumptions = await ref.watch(
    projectionAssumptionsProvider.future,
  );
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
  return RetirementProjection.fromLiveData(
    today: DateTime.now(),
    assumptions: assumptions,
    accounts: accounts.values.toList(),
    ownedAssets: ownedAssets,
    transactions: transactions,
    categories: categories,
  );
});

/// Saves assumption changes (JSON-shaped keys, see
/// [ProjectionAssumptions.merged]) to the synced row and refreshes screens.
class ProjectionAssumptionsEditor(final Ref _ref) {
  Future<ProjectionAssumptions> apply(Map<String, dynamic> changes) async {
    final ProjectionSettingsRepository repository = await _ref.read(
      projectionSettingsRepositoryProvider.future,
    );
    final updated = (await repository.loadAssumptions()).merged(changes);
    await repository.saveAssumptions(updated);
    _ref.read(spendDataChangedProvider.notifier).notify();
    return updated;
  }
}

final projectionAssumptionsEditorProvider =
    Provider<ProjectionAssumptionsEditor>(ProjectionAssumptionsEditor.new);
