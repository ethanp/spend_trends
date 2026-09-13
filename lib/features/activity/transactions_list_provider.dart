import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';

final transactionsListProvider = FutureProvider<List<BankTransaction>>((
  ref,
) async {
  ref.watch(spendDataChangedProvider);
  final repository = await ref.watch(transactionsRepositoryProvider.future);
  return repository.listAll();
});
