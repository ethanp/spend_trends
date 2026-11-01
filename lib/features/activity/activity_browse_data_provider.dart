import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/activity/transactions_list_provider.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:spend_trends/services/sqlite/categories_repository.dart';

/// Activity list + filters in one reload so rows do not flicker across waves.
class const ActivityBrowseData({
  required final List<BankTransaction> transactions,
  required final Map<String, Account> accounts,
  required final Map<String, SpendCategory> categories,
  required final List<CategorizationRule> rules,
});

final activityBrowseDataProvider = FutureProvider<ActivityBrowseData>((
  ref,
) async {
  final List<BankTransaction> transactions = await ref.watch(
    transactionsListProvider.future,
  );
  final categoriesRepository = await ref.watch(
    categoriesRepositoryProvider.future,
  );
  final accountsRepository = await ref.watch(accountsRepositoryProvider.future);
  final List<Account> accountsList = await accountsRepository.listAccounts();
  final List<SpendCategory> categories = await categoriesRepository
      .listActive();
  final List<CategorizationRule> rules = await categoriesRepository.listRules();

  return ActivityBrowseData(
    transactions: transactions,
    accounts: {for (final account in accountsList) account.id: account},
    categories: {for (final category in categories) category.id: category},
    rules: rules,
  );
});
