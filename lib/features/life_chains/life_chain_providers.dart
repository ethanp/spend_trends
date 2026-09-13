import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/stay_chain.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/chain_stays_repository.dart';

final housingChainProvider = FutureProvider<StayChain>((ref) async {
  ref.watch(spendDataChangedProvider);
  final repository = await ref.watch(housingStaysRepositoryProvider.future);
  return repository.loadChain();
});

final jobChainProvider = FutureProvider<StayChain>((ref) async {
  ref.watch(spendDataChangedProvider);
  final repository = await ref.watch(jobStaysRepositoryProvider.future);
  return repository.loadChain();
});
