/// Built-in categories with stable ids (`cat_housing`, `cat_income`,
/// `cat_transfer`, `cat_investments`). Older data could:
/// - lack those rows entirely
/// - store Copilot `transaction_type` income/transfer as a *user* category lock
///   (so Activity treated them as manual instead of auto-categorized)
/// - have duplicate named "Housing"/"Income"/"Transfer"/"Investments"
///   categories from seeds or early imports
///
/// This startup migration upserts the specials, moves type-derived locks onto
/// `suggested_category_id`, backfills suggested from `transaction_type`,
/// merges duplicate-named categories onto the canonical ids, and puts Income
/// + Investments in the Income group. Idempotent.
library;

import 'package:spend_trends/domain/special_category.dart';
import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:powersync/powersync.dart';

const _log = ELogger('SpecialCategories');

Future<void> ensureSpecialCategoriesMigrated(PowerSyncDatabase database) async {
  await ensureIncomeCategoryGroup(database);
  await _upsertSpecialCategories(database);
  await _releaseTypeDerivedUserLocks(database);
  await _backfillFromTransactionType(database);
  await _mergeDuplicateNamedCategories(database);
}

Future<void> ensureIncomeCategoryGroup(PowerSyncDatabase database) async {
  final existing = await database.getOptional(
    'SELECT id FROM category_groups WHERE id = ?',
    [SpecialCategory.incomeGroupId],
  );
  if (existing != null) return;
  await database.upsert('category_groups', {
    'id': SpecialCategory.incomeGroupId,
    'name': SpecialCategory.incomeGroupName,
    'sort_order': SpecialCategory.incomeGroupSortOrder,
  });
}

Future<void> _upsertSpecialCategories(PowerSyncDatabase database) async {
  for (final special in SpecialCategory.values) {
    final existing = await database.getOptional(
      'SELECT group_id, conscious_spending_area FROM categories WHERE id = ?',
      [special.id],
    );
    final existingGroupId = existing?['group_id'] as String?;
    final existingArea = existing?['conscious_spending_area'] as String?;
    await database.upsert('categories', {
      'id': special.id,
      'name': special.name,
      'sort_order': special.sortOrder,
      'archived': 0,
      'color_token': null,
      'group_id': existingGroupId ?? special.defaultGroupId,
      'conscious_spending_area':
          existingArea ?? special.defaultConsciousSpendingArea?.storageValue,
    });
  }
}

/// Older builds wrote type-derived Income/Transfer onto [user_category_id], which
/// made Activity treat them as manual. Move those locks to suggested.
Future<void> _releaseTypeDerivedUserLocks(PowerSyncDatabase database) async {
  await database.execute(
    '''
    UPDATE transactions
    SET user_category_id = NULL, suggested_category_id = ?
    WHERE user_category_id = ?
      AND lower(trim(coalesce(transaction_type, ''))) = 'income'
    ''',
    [SpecialCategory.income.id, SpecialCategory.income.id],
  );
  await database.execute(
    '''
    UPDATE transactions
    SET user_category_id = NULL, suggested_category_id = ?
    WHERE user_category_id = ?
      AND lower(trim(coalesce(transaction_type, ''))) IN (
        'transfer',
        'internal transfer'
      )
    ''',
    [SpecialCategory.transfer.id, SpecialCategory.transfer.id],
  );
}

/// Copilot / import `transaction_type` → suggested category (not a user lock).
Future<void> _backfillFromTransactionType(PowerSyncDatabase database) async {
  await database.execute(
    '''
    UPDATE transactions
    SET suggested_category_id = ?
    WHERE lower(trim(coalesce(transaction_type, ''))) = 'income'
      AND (user_category_id IS NULL OR trim(user_category_id) = '')
    ''',
    [SpecialCategory.income.id],
  );
  await database.execute(
    '''
    UPDATE transactions
    SET suggested_category_id = ?
    WHERE lower(trim(coalesce(transaction_type, ''))) IN (
      'transfer',
      'internal transfer'
    )
      AND (user_category_id IS NULL OR trim(user_category_id) = '')
    ''',
    [SpecialCategory.transfer.id],
  );
  _log.fine('Backfilled special categories from transaction_type');
}

Future<void> _mergeDuplicateNamedCategories(PowerSyncDatabase database) async {
  for (final special in SpecialCategory.values) {
    final duplicateRows = await database.getAll(
      '''
      SELECT id FROM categories
      WHERE lower(trim(name)) = ?
        AND id != ?
      ''',
      [special.name.toLowerCase(), special.id],
    );
    for (final row in duplicateRows) {
      final duplicateId = row['id'] as String;
      await database.execute(
        'UPDATE transactions SET user_category_id = ? WHERE user_category_id = ?',
        [special.id, duplicateId],
      );
      await database.execute(
        '''
        UPDATE transactions
        SET suggested_category_id = ?
        WHERE suggested_category_id = ?
        ''',
        [special.id, duplicateId],
      );
      await database.execute(
        'UPDATE categorization_rules SET category_id = ? WHERE category_id = ?',
        [special.id, duplicateId],
      );
      await database.execute('DELETE FROM categories WHERE id = ?', [
        duplicateId,
      ]);
      _log.log(
        'Merged duplicate "${special.name}" ($duplicateId) → ${special.id}',
      );
    }
  }
}
