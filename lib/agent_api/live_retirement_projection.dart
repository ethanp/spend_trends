import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/agent_api/categorization_snapshot.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/services/sqlite/owned_assets_repository.dart';
import 'package:spend_trends/services/sqlite/projection_settings_repository.dart';

/// The retirement projection read straight from the repositories. Screen
/// providers pause while their tab is hidden, so the API never reads them.
class const LiveRetirementProjection({
  required final ProviderContainer container,
}) {
  Future<RetirementProjection> load() async {
    final snapshot = await CategorizationSnapshot.load(container);
    final OwnedAssetsRepository ownedAssetsRepository = await container.read(
      ownedAssetsRepositoryProvider.future,
    );
    final ProjectionSettingsRepository settingsRepository = await container
        .read(projectionSettingsRepositoryProvider.future);
    return RetirementProjection.fromLiveData(
      today: DateTime.now(),
      assumptions: await settingsRepository.loadAssumptions(),
      accounts: snapshot.accounts,
      ownedAssets: await ownedAssetsRepository.listWithValuations(),
      transactions: snapshot.transactions,
      categories: snapshot.categories,
    );
  }
}
