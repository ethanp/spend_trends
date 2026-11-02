import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/domain/categories/category_spend_pace.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';
import 'package:spend_trends/data/repositories/categories_repository.dart';
import 'package:spend_trends/data/repositories/transactions_repository.dart';

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
