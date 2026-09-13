import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/remove_copilot_duplicates.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';

final removeCopilotDuplicatesProvider = FutureProvider<RemoveCopilotDuplicates>(
  (ref) async {
    return RemoveCopilotDuplicates(
      accountsRepository: await ref.watch(accountsRepositoryProvider.future),
      transactionsRepository: await ref.watch(
        transactionsRepositoryProvider.future,
      ),
    );
  },
);
