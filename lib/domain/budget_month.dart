import 'package:spend_trends/domain/month_summary.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/trends/annual_pace_smoother.dart';
import 'package:spend_trends/features/trends/hann_annual_pace_kernel.dart';
import 'package:spend_trends/features/trends/trend_chart_catalog.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:spend_trends/services/sqlite/categories_repository.dart';
import 'package:spend_trends/services/sqlite/simplefin_pull_history.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';
import 'package:ethan_utils/ethan_utils.dart';

class BudgetMonth({
  required final AccountsRepository _accountsRepository,
  required final TransactionsRepository _transactionsRepository,
  required final CategoriesRepository _categoriesRepository,
  required final SimpleFinPullHistory _simpleFinPullHistory,
}) {
  Future<MonthSummary> snapshot(String yearMonth) async {
    final accounts = await _accountsRepository.listAccounts();
    final names = {
      for (final account in accounts)
        account.id: account.displayNameWithInstitution,
    };
    return _transactionsRepository.monthSummary(
      yearMonth: yearMonth,
      accountNames: names,
      lastSyncedAt: await _simpleFinPullHistory.lastSuccessfulPullAt(),
    );
  }

  Future<List<CategoryMonthRow>> categoryRows(String yearMonth) async {
    final categories = await _categoriesRepository.listActive();
    final monthOutflows = _outflowByCategory(
      await _transactionsRepository.listForMonth(yearMonth),
    );
    final trailingYearOutflows = _outflowByCategory(
      await _transactionsRepository.listPostedInLastDays(
        HannAnnualPaceKernel.defaultYearDays,
      ),
    );
    final observedDays = _observedTrailingDays();

    return [
      for (final category in categories)
        if (!category.isFlow)
          CategoryMonthRow(
            categoryId: category.id,
            categoryName: category.name,
            annualizedSpendCents: AnnualPaceSmoother.annualizeTrailingTotal(
              windowTotalCents: (trailingYearOutflows[category.id] ?? 0)
                  .toDouble(),
              observedDays: observedDays,
            ).round(),
            spentCents: monthOutflows[category.id] ?? 0,
          ),
    ];
  }

  /// Calendar days on or after [chartHistoryStart] inside the trailing window.
  static int _observedTrailingDays() {
    final today = DateTime.now().startOfDay;
    final historyFloor = TrendChartCatalog.chartHistoryStart.startOfDay;
    final windowFloor = today.shiftedByDays(
      -(HannAnnualPaceKernel.defaultYearDays - 1),
    );
    final effectiveFloor = windowFloor.isBefore(historyFloor)
        ? historyFloor
        : windowFloor;
    final observedDays = today.difference(effectiveFloor).inDays + 1;
    if (observedDays < 1) return 1;
    if (observedDays > HannAnnualPaceKernel.defaultYearDays) {
      return HannAnnualPaceKernel.defaultYearDays;
    }
    return observedDays;
  }

  String currentYearMonth() => DateTime.now().yearMonthKey;

  static Map<String, int> _outflowByCategory(
    List<BankTransaction> transactions,
  ) {
    final spentByCategory = <String, int>{};
    for (final transaction in transactions) {
      if (transaction.excluded) continue;
      if (!transaction.isOutflow) continue;
      final categoryId = transaction.categoryId;
      if (categoryId == null) continue;
      spentByCategory.update(
        categoryId,
        (priorSpendCents) => priorSpendCents + -transaction.amountCents,
        ifAbsent: () => -transaction.amountCents,
      );
    }
    return spentByCategory;
  }
}
