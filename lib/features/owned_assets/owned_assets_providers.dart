import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/owned_asset.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/owned_assets_repository.dart';

final ownedAssetsListProvider = FutureProvider<List<OwnedAssetWithValuations>>((
  ref,
) async {
  ref.watch(spendDataChangedProvider);
  final repository = await ref.watch(ownedAssetsRepositoryProvider.future);
  return repository.listWithValuations();
});
