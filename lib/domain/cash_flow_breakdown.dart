import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';

/// What one transaction adds to take-home pay, spending, money moved between
/// accounts, and one conscious spending area. Signed: a refund is negative
/// spending, a withdrawal is a negative investment.
class const CashFlowContribution({
  final int takeHomeCents = 0,
  final int spendingCents = 0,
  final int transferCents = 0,
  final ConsciousSpendingArea? area,
  final int areaCents = 0,
}) {
  static const none = CashFlowContribution();

  int get savingsCents => takeHomeCents - spendingCents;
}

/// Ramit Sethi's conscious spending plan read from bank activity.
///
/// - Take-home pay is Income on cash accounts: paychecks, plus RSU sale
///   proceeds once they reach checking (stock compensation). Dividends and
///   stock sales still inside investment accounts are returns, not pay.
/// - Spending is spend-category and uncategorized activity; refunds net
///   against their category.
/// - Investments are net money put in, from the Investments category:
///   deposits leaving cash accounts (brokerages, crypto) add and money coming
///   back from them subtracts; on investment accounts, payroll contributions
///   add. RSU sale proceeds are Income, not a withdrawal, so they never
///   subtract here. Transfer activity on investment accounts
///   (buys, sells, the brokerage side of a deposit) counts nowhere, so
///   nothing doubles.
/// - Cash moved into savings accounts is parked, not a bucket; it shows only
///   in net worth.
/// - Spend-side activity on loan accounts (payment records, escrow
///   disbursements) restates payments already spent from the paying account,
///   so it counts nowhere.
class CashFlowBreakdown({
  required List<SpendCategory> categories,
  required List<Account> accounts,
}) {
  final Map<String, ConsciousSpendingArea> _areaByCategoryId = {
    for (final category in categories)
      if (category.consciousSpendingArea != null)
        category.id: category.consciousSpendingArea!,
  };
  final Map<String, AccountKind> _kindByAccountId = {
    for (final account in accounts) account.id: account.kind,
  };

  CashFlowContribution contributionOf(BankTransaction transaction) {
    final categoryId = transaction.categoryId;
    final accountKind = _kindByAccountId[transaction.accountId];
    final amountCents = transaction.amountCents;

    if (SpecialCategory.isAssetSaleId(categoryId)) {
      return CashFlowContribution.none;
    }
    if (SpecialCategory.isInvestmentsId(categoryId)) {
      return CashFlowContribution(
        area: ConsciousSpendingArea.investments,
        areaCents: accountKind == AccountKind.investment
            ? amountCents
            : -amountCents,
      );
    }
    if (SpecialCategory.isTransferId(categoryId)) {
      return CashFlowContribution(transferCents: amountCents.abs());
    }
    if (SpecialCategory.isIncomeId(categoryId)) {
      if (accountKind == AccountKind.investment) {
        return CashFlowContribution.none;
      }
      return CashFlowContribution(takeHomeCents: amountCents);
    }
    if (transaction.excluded) return CashFlowContribution.none;
    if (accountKind == AccountKind.loans) return CashFlowContribution.none;
    return CashFlowContribution(
      spendingCents: -amountCents,
      area: categoryId == null ? null : _areaByCategoryId[categoryId],
      areaCents: -amountCents,
    );
  }
}
