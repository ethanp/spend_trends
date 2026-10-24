/// Built-in categories with stable ids ([SpecialCategory]). Older data could
/// lack those rows or have duplicate-named copies from seeds or imports.
///
/// This startup migration upserts the specials, merges duplicate-named
/// categories (and their rules) onto the canonical ids, and puts Income in
/// the Income group. Idempotent.
library;

import 'package:spend_trends/domain/special_category.dart';
import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:powersync/powersync.dart';

const _log = ELogger('SpecialCategories');

Future<void> ensureSpecialCategoriesMigrated(PowerSyncDatabase database) async {
  await ensureIncomeCategoryGroup(database);
  await _upsertSpecialCategories(database);
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
        'UPDATE transactions SET category_id = ? WHERE category_id = ?',
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
