import 'package:spend_trends/domain/accounts/account.dart';
import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';
import 'package:ethan_utils/ethan_utils.dart';

/// Case-insensitive substring match; space-separated terms are ANDed.
bool activityMatchesSearch({
  required BankTransaction transaction,
  required String query,
  Account? account,
  SpendCategory? category,
}) {
  final searchTerms = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty);
  if (searchTerms.isEmpty) return true;

  final haystack = [
    transaction.rawDescription,
    transaction.normalizedMerchant,
    account?.displayNameWithInstitution ?? '',
    account?.institutionDisplayName ?? '',
    category?.name ?? 'Uncategorized',
    transaction.note ?? '',
    transaction.transactionType ?? '',
    transaction.recurringSeries ?? '',
    formatCents(transaction.amountCents),
  ].join('\n').toLowerCase();

  for (final term in searchTerms) {
    if (!haystack.contains(term)) return false;
  }
  return true;
}
