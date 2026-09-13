import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/budget_month.dart';
import 'package:spend_trends/domain/categorizer.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/month_summary.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:spend_trends/services/sqlite/categories_repository.dart';
import 'package:spend_trends/services/sqlite/simplefin_pull_history.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';

final categorizerProvider = FutureProvider<Categorizer>((ref) async {
  return Categorizer(
    categoriesRepository: await ref.watch(categoriesRepositoryProvider.future),
    transactionsRepository: await ref.watch(
      transactionsRepositoryProvider.future,
    ),
  );
});

final budgetMonthProvider = FutureProvider<BudgetMonth>((ref) async {
  return BudgetMonth(
    accountsRepository: await ref.watch(accountsRepositoryProvider.future),
    transactionsRepository: await ref.watch(
      transactionsRepositoryProvider.future,
    ),
    categoriesRepository: await ref.watch(categoriesRepositoryProvider.future),
    simpleFinPullHistory: await ref.watch(simpleFinPullHistoryProvider.future),
  );
});

final categoryMonthRowsProvider =
    FutureProvider.family<List<CategoryMonthRow>, String>((
      ref,
      yearMonth,
    ) async {
      ref.watch(spendDataChangedProvider);
      final budgetMonth = await ref.watch(budgetMonthProvider.future);
      return budgetMonth.categoryRows(yearMonth);
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

final currentYearMonthProvider = Provider<String>((ref) {
  return DateTime.now().yearMonthKey;
});
