import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/domain/categories/special_category.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';
import 'package:spend_trends/domain/trends/hann_annual_pace_kernel.dart';

/// Trailing windows a category's spend is averaged over, longest first.
enum CategorySpendWindow({
  required final int days,
  required final String label,
}) {
  twoYears(days: 730, label: '2y'),
  oneYear(days: 365, label: '1y'),
  sixMonths(days: 183, label: '6mo'),
  threeMonths(days: 91, label: '3mo'),
}

/// One category's average monthly spend over each [CategorySpendWindow]
/// ending today. A window reaching before chart history averages only the
/// days it covers.
class const CategorySpendPace({
  required final String categoryId,
  required final String categoryName,
  required final Map<CategorySpendWindow, int> monthlyCentsByWindow,
}) {
  int monthlyCents(CategorySpendWindow window) =>
      monthlyCentsByWindow[window] ?? 0;

  /// The pace annual-burn totals and ranking read.
  int get oneYearAnnualCents => monthlyCents(CategorySpendWindow.oneYear) * 12;

  static List<CategorySpendPace> forCategories({
    required DateTime now,
    required List<BankTransaction> transactions,
    required List<SpendCategory> categories,
  }) {
    final DateTime today = now.startOfDay;
    final monthlyCentsByCategoryId = <String, Map<CategorySpendWindow, int>>{};
    for (final window in CategorySpendWindow.values) {
      final DateTime windowStart = _windowStart(window, today);
      final int coveredDays = today.difference(windowStart).inDays + 1;
      final outflowByCategoryId = _outflowByCategoryId(
        transactions,
        fromDay: windowStart,
        beforeMillis: now.millisecondsSinceEpoch,
      );
      for (final MapEntry(key: categoryId, value: outflowCents)
          in outflowByCategoryId.entries) {
        monthlyCentsByCategoryId.putIfAbsent(categoryId, () => {})[window] =
            (outflowCents *
                    HannAnnualPaceKernel.defaultYearDays /
                    coveredDays /
                    12)
                .round();
      }
    }
    return [
      for (final category in categories)
        if (!category.isFlow)
          CategorySpendPace(
            categoryId: category.id,
            categoryName: category.name,
            monthlyCentsByWindow: monthlyCentsByCategoryId[category.id] ?? {},
          ),
    ];
  }

  static DateTime _windowStart(CategorySpendWindow window, DateTime today) {
    final DateTime fullWindowStart = today.shiftedByDays(-(window.days - 1));
    final DateTime historyStart =
        BankTransaction.completeHistoryStart.startOfDay;
    return fullWindowStart.isBefore(historyStart)
        ? historyStart
        : fullWindowStart;
  }

  static Map<String, int> _outflowByCategoryId(
    List<BankTransaction> transactions, {
    required DateTime fromDay,
    required int beforeMillis,
  }) {
    final int fromMillis = fromDay.millisecondsSinceEpoch;
    final outflowByCategoryId = <String, int>{};
    for (final transaction in transactions) {
      if (!transaction.isOutflow) continue;
      final String? categoryId = transaction.categoryId;
      if (categoryId == null) continue;
      if (transaction.postedAtMillis < fromMillis ||
          transaction.postedAtMillis >= beforeMillis) {
        continue;
      }
      outflowByCategoryId.update(
        categoryId,
        (priorOutflowCents) => priorOutflowCents - transaction.amountCents,
        ifAbsent: () => -transaction.amountCents,
      );
    }
    return outflowByCategoryId;
  }
}
