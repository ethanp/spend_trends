import 'package:spend_trends/domain/categorizer.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:spend_trends/services/sqlite/categories_repository.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';

class const CopilotDefaultRuleMigrationResult({
  required final int defaultImportRulesDeleted,
  required final int transactionsReleased,
});

class const CopilotDefaultRuleMigrationProgress({
  required final int completed,
  required final int total,
}) {
  double get fraction => total <= 0 ? 0 : completed / total;
}

/// Releases Copilot user-locked categories to suggested (no merchant rules).
///
/// Also deletes leftover priority-0 “default import” contains rules that were
/// incorrectly created from merchant names in earlier migrations/imports.
class CopilotDefaultRuleMigration({
  required final AccountsRepository _accountsRepository,
  required final TransactionsRepository _transactionsRepository,
  required final CategoriesRepository _categoriesRepository,
  required final Categorizer _categorizer,
}) {
  Future<CopilotDefaultRuleMigrationResult> run({
    void Function(CopilotDefaultRuleMigrationProgress progress)? onProgress,
  }) async {
    final copilotAccountIds = await _copilotAccountIds();
    final transactions = await _transactionsRepository.listAll();
    final candidates = _lockedCopilotTransactions(
      transactions,
      copilotAccountIds,
    );
    final defaultImportRules = [
      for (final rule in await _categoriesRepository.listRules())
        if (rule.isDefaultImport) rule,
    ];

    final totalSteps =
        candidates.length + defaultImportRules.length + transactions.length;
    void report(int completed) {
      onProgress?.call(
        CopilotDefaultRuleMigrationProgress(
          completed: completed,
          total: totalSteps,
        ),
      );
    }

    report(0);
    final transactionsReleased = await _releaseUserCategories(
      candidates,
      onReleased: report,
    );
    final defaultImportRulesDeleted = await _deleteDefaultImportRules(
      defaultImportRules,
      onDeleted: (deletedCount) => report(candidates.length + deletedCount),
    );
    await _categorizer.applyRulesToUncategorized(
      onProgress: (completed, _) {
        report(candidates.length + defaultImportRules.length + completed);
      },
    );
    report(totalSteps);

    return CopilotDefaultRuleMigrationResult(
      defaultImportRulesDeleted: defaultImportRulesDeleted,
      transactionsReleased: transactionsReleased,
    );
  }

  Future<Set<String>> _copilotAccountIds() async {
    final accounts = await _accountsRepository.listAccounts();
    return {
      for (final account in accounts)
        if (account.isCopilot) account.id,
    };
  }

  List<BankTransaction> _lockedCopilotTransactions(
    List<BankTransaction> transactions,
    Set<String> copilotAccountIds,
  ) {
    return [
      for (final transaction in transactions)
        if (copilotAccountIds.contains(transaction.accountId) &&
            transaction.hasUserCategory)
          transaction,
    ];
  }

  Future<int> _releaseUserCategories(
    List<BankTransaction> candidates, {
    required void Function(int releasedCount) onReleased,
  }) async {
    var transactionsReleased = 0;
    for (var index = 0; index < candidates.length; index++) {
      final transaction = candidates[index];
      await _transactionsRepository.releaseUserCategoryToSuggested(
        transactionId: transaction.id,
        categoryId: transaction.userCategoryId!,
      );
      transactionsReleased++;
      onReleased(index + 1);
    }
    return transactionsReleased;
  }

  Future<int> _deleteDefaultImportRules(
    List<CategorizationRule> defaultImportRules, {
    required void Function(int deletedCount) onDeleted,
  }) async {
    var defaultImportRulesDeleted = 0;
    for (var index = 0; index < defaultImportRules.length; index++) {
      await _categoriesRepository.deleteRule(defaultImportRules[index].id);
      defaultImportRulesDeleted++;
      onDeleted(index + 1);
    }
    return defaultImportRulesDeleted;
  }
}
