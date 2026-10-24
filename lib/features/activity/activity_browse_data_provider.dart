import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:spend_trends/services/sqlite/categories_repository.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';

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
  ref.watch(spendDataChangedProvider);
  final transactionsRepository = await ref.watch(
    transactionsRepositoryProvider.future,
  );
  final categoriesRepository = await ref.watch(
    categoriesRepositoryProvider.future,
  );
  final accountsRepository = await ref.watch(accountsRepositoryProvider.future);

  final reload = await Future.wait([
    transactionsRepository.listAll(),
    accountsRepository.listAccounts(),
    categoriesRepository.listActive(),
    categoriesRepository.listRules(),
  ]);

  final transactions = reload[0] as List<BankTransaction>;
  final accountsList = reload[1] as List<Account>;
  final categories = reload[2] as List<SpendCategory>;
  final rules = reload[3] as List<CategorizationRule>;

  return ActivityBrowseData(
    transactions: transactions,
    accounts: {for (final account in accountsList) account.id: account},
    categories: {for (final category in categories) category.id: category},
    rules: rules,
  );
});
