import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/categorizer.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/category_spend_pace.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/activity/transactions_list_provider.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/categories_repository.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';

final categorizerProvider = FutureProvider<Categorizer>((ref) async {
  return Categorizer(
    categoriesRepository: await ref.watch(categoriesRepositoryProvider.future),
    transactionsRepository: await ref.watch(
      transactionsRepositoryProvider.future,
    ),
  );
});

final categorySpendPacesProvider = FutureProvider<List<CategorySpendPace>>((
  ref,
) async {
  final List<BankTransaction> transactions = await ref.watch(
    transactionsListProvider.future,
  );
  final List<SpendCategory> categories = await ref.watch(
    categoriesListProvider.future,
  );
  return CategorySpendPace.forCategories(
    now: DateTime.now(),
    transactions: transactions,
    categories: categories,
  );
});

final categoriesListProvider = FutureProvider<List<SpendCategory>>((ref) async {
  ref.watch(spendDataChangedProvider);
  final repository = await ref.watch(categoriesRepositoryProvider.future);
  return repository.listActive();
});

final categoryGroupsProvider = FutureProvider<List<CategoryGroup>>((ref) async {
  ref.watch(spendDataChangedProvider);
  final repository = await ref.watch(categoriesRepositoryProvider.future);
  return repository.listGroups();
});

final categorizationRulesProvider = FutureProvider<List<CategorizationRule>>((
  ref,
) async {
  ref.watch(spendDataChangedProvider);
  final repository = await ref.watch(categoriesRepositoryProvider.future);
  return repository.listRules();
});
