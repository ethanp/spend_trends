import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/copilot_default_rule_migration.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:spend_trends/services/sqlite/categories_repository.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';

final copilotDefaultRuleMigrationProvider =
    FutureProvider<CopilotDefaultRuleMigration>((ref) async {
      return CopilotDefaultRuleMigration(
        accountsRepository: await ref.watch(accountsRepositoryProvider.future),
        transactionsRepository: await ref.watch(
          transactionsRepositoryProvider.future,
        ),
        categoriesRepository: await ref.watch(
          categoriesRepositoryProvider.future,
        ),
        categorizer: await ref.watch(categorizerProvider.future),
      );
    });
