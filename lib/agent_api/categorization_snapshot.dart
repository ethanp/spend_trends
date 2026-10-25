import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:spend_trends/services/sqlite/categories_repository.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';

/// One consistent read of categories, rules, accounts, and transactions,
/// rendered as JSON with the context an agent needs to judge a category:
/// account, category role, the rule that set it (with its note), and the
/// transaction note.
class CategorizationSnapshot({
  required final List<SpendCategory> categories,
  required final List<CategoryGroup> groups,
  required final List<Account> accounts,
  required final List<CategorizationRule> rules,
  required final List<BankTransaction> transactions,
}) {
  late final Map<String, SpendCategory> categoriesById = {
    for (final category in categories) category.id: category,
  };
  late final Map<String, CategoryGroup> groupsById = {
    for (final group in groups) group.id: group,
  };
  late final Map<String, Account> accountsById = {
    for (final account in accounts) account.id: account,
  };
  late final Map<String, CategorizationRule> rulesById = {
    for (final rule in rules) rule.id: rule,
  };

  static Future<CategorizationSnapshot> load(
    ProviderContainer container,
  ) async {
    final CategoriesRepository categoriesRepository = await container.read(
      categoriesRepositoryProvider.future,
    );
    final AccountsRepository accountsRepository = await container.read(
      accountsRepositoryProvider.future,
    );
    final TransactionsRepository transactionsRepository = await container.read(
      transactionsRepositoryProvider.future,
    );
    return CategorizationSnapshot(
      categories: await categoriesRepository.listAll(),
      groups: await categoriesRepository.listGroups(),
      accounts: await accountsRepository.listAccounts(),
      rules: await categoriesRepository.listRules(),
      transactions: await transactionsRepository.listAll(),
    );
  }

  Map<String, Object?> transactionJson(BankTransaction transaction) {
    final account = accountsById[transaction.accountId];
    final CategorizationRule? categoryRule =
        rulesById[transaction.categoryRuleId];
    return {
      'id': transaction.id,
      'postedOn': transaction.postedAt.dayKey,
      'amountCents': transaction.amountCents,
      'amount': formatCents(transaction.amountCents),
      'description': transaction.rawDescription,
      'merchant': transaction.normalizedMerchant,
      'pending': transaction.pending,
      'excluded': transaction.excluded,
      'note': transaction.note,
      'recurringSeries': transaction.recurringSeries,
      'account': {
        'id': transaction.accountId,
        'name': account?.displayNameWithInstitution,
        'kind': account?.kind.name,
      },
      'category': _categoryRef(transaction.categoryId),
      'categorySource': categorySource(transaction),
      'categoryRule': categoryRule == null ? null : _ruleRef(categoryRule),
    };
  }

  Map<String, Object?> categoryJson(SpendCategory category) {
    final group = category.groupId == null
        ? null
        : groupsById[category.groupId];
    return {
      'id': category.id,
      'name': category.name,
      'role': _categoryRole(category),
      'archived': category.archived,
      'builtIn': SpecialCategory.isSpecialId(category.id),
      'locked': category.lockedCaption != null,
      'group': group == null ? null : {'id': group.id, 'name': group.name},
      'consciousSpendingArea': category.consciousSpendingArea?.name,
      'transactionCount': _transactionCountByCategoryId[category.id] ?? 0,
      'trailingYearOutflowCents':
          _trailingYearOutflowByCategoryId[category.id] ?? 0,
      'ruleCount': _ruleCountByCategoryId[category.id] ?? 0,
    };
  }

  Map<String, Object?> ruleJson(CategorizationRule rule) {
    return {
      ..._ruleRef(rule),
      'category': _categoryRef(rule.categoryId),
      'account': rule.accountId == null
          ? null
          : {
              'id': rule.accountId,
              'name': accountsById[rule.accountId]?.displayNameWithInstitution,
            },
      'transactionCount': _transactionCountByRuleId[rule.id] ?? 0,
    };
  }

  Map<String, Object?> accountJson(Account account) {
    return {
      'id': account.id,
      'name': account.displayNameWithInstitution,
      'kind': account.kind.name,
      'balanceCents': account.balanceCents,
      'balanceAsOf': account.balanceAsOf?.dayKey,
      'source': account.sourceName,
      'taxTreatment': account.taxTreatment.name,
      'taxTreatmentIsAutomatic': account.chosenTaxTreatment == null,
      'belongsToAccountId': account.belongsToAccountId,
      'transactionCount': _transactionCountByAccountId[account.id] ?? 0,
    };
  }

  Map<String, Object?>? _categoryRef(String? categoryId) {
    if (categoryId == null) return null;
    final category = categoriesById[categoryId];
    return {
      'id': categoryId,
      'name': category?.name,
      'role': category == null ? null : _categoryRole(category),
    };
  }

  Map<String, Object?> _ruleRef(CategorizationRule rule) => {
    'id': rule.id,
    'pattern': rule.pattern,
    'matchType': rule.matchType.storageValue,
    'categoryId': rule.categoryId,
    'accountId': rule.accountId,
    'note': rule.note,
  };

  /// `rule` = categorized by a rule; `unruled` = carries a category from
  /// before rules-only categorization and needs a rule; `none` = uncategorized.
  String categorySource(BankTransaction transaction) {
    if (transaction.categoryRuleId != null) return 'rule';
    if (transaction.categoryId != null) return 'unruled';
    return 'none';
  }

  String _categoryRole(SpendCategory category) {
    if (category.isIncome) return 'income';
    if (category.isInvestments) return 'investments';
    if (category.isTransfer) return 'transfer';
    if (category.isAssetSale) return 'assetSale';
    return 'spend';
  }

  late final Map<String, int> _transactionCountByCategoryId = () {
    final countByCategoryId = <String, int>{};
    for (final transaction in transactions) {
      final categoryId = transaction.categoryId;
      if (categoryId == null) continue;
      countByCategoryId.update(
        categoryId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return countByCategoryId;
  }();

  late final Map<String, int> _trailingYearOutflowByCategoryId = () {
    final yearAgo = DateTime.now().shiftedByDays(-365);
    final outflowByCategoryId = <String, int>{};
    for (final transaction in transactions) {
      final categoryId = transaction.categoryId;
      if (categoryId == null) continue;
      if (transaction.excluded || !transaction.isOutflow) continue;
      if (transaction.postedAt.isBefore(yearAgo)) continue;
      outflowByCategoryId.update(
        categoryId,
        (priorCents) => priorCents - transaction.amountCents,
        ifAbsent: () => -transaction.amountCents,
      );
    }
    return outflowByCategoryId;
  }();

  late final Map<String, int> _ruleCountByCategoryId = () {
    final countByCategoryId = <String, int>{};
    for (final rule in rules) {
      countByCategoryId.update(
        rule.categoryId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return countByCategoryId;
  }();

  late final Map<String, int> _transactionCountByRuleId = () {
    final countByRuleId = <String, int>{};
    for (final transaction in transactions) {
      final ruleId = transaction.categoryRuleId;
      if (ruleId == null) continue;
      countByRuleId.update(ruleId, (count) => count + 1, ifAbsent: () => 1);
    }
    return countByRuleId;
  }();

  late final Map<String, int> _transactionCountByAccountId = () {
    final countByAccountId = <String, int>{};
    for (final transaction in transactions) {
      countByAccountId.update(
        transaction.accountId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return countByAccountId;
  }();
}
