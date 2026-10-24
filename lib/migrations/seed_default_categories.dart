/// Fresh installs have an empty `categories` table. The app assumes a fixed set
/// of default spend buckets (Groceries, Dining, …) plus built-ins (Housing,
/// Income, Transfer, Investments) so Copilot import mapping and Trends series
/// have somewhere to land.
///
/// This runs once at PowerSync startup when `categories` is empty. It is a no-op
/// after the first seed (or after sync has already pulled categories).
library;

import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/migrations/migrate_special_categories.dart';
import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:powersync/powersync.dart';

const _log = ELogger('SeedDefaultCategories');

class const _DefaultSpendCategory({
  required final String name,
  required final ConsciousSpendingArea area,
});

Future<void> seedDefaultCategoriesIfNeeded(PowerSyncDatabase database) async {
  final countRow = await database.getOptional(
    'SELECT COUNT(*) AS c FROM categories',
  );
  final count = (countRow?['c'] as Object?).asIntOrNull() ?? 0;
  if (count > 0) return;

  await ensureIncomeCategoryGroup(database);

  const spendDefaults = [
    _DefaultSpendCategory(
      name: 'Groceries',
      area: ConsciousSpendingArea.fixedCosts,
    ),
    _DefaultSpendCategory(
      name: 'Dining',
      area: ConsciousSpendingArea.guiltFree,
    ),
    _DefaultSpendCategory(
      name: 'Transport',
      area: ConsciousSpendingArea.fixedCosts,
    ),
    _DefaultSpendCategory(
      name: 'Utilities',
      area: ConsciousSpendingArea.fixedCosts,
    ),
    _DefaultSpendCategory(
      name: 'Entertainment',
      area: ConsciousSpendingArea.guiltFree,
    ),
    _DefaultSpendCategory(
      name: 'Shopping',
      area: ConsciousSpendingArea.guiltFree,
    ),
    _DefaultSpendCategory(
      name: 'Health',
      area: ConsciousSpendingArea.fixedCosts,
    ),
    _DefaultSpendCategory(
      name: 'Travel',
      area: ConsciousSpendingArea.guiltFree,
    ),
    _DefaultSpendCategory(name: 'Other', area: ConsciousSpendingArea.guiltFree),
  ];
  for (var index = 0; index < spendDefaults.length; index++) {
    final seed = spendDefaults[index];
    await database.upsert('categories', {
      'id': 'cat_${seed.name.toLowerCase()}',
      'name': seed.name,
      'sort_order': index >= 3 ? index + 1 : index,
      'archived': 0,
      'color_token': null,
      'group_id': null,
      'conscious_spending_area': seed.area.storageValue,
    });
  }
  for (final special in SpecialCategory.values) {
    await database.upsert('categories', {
      'id': special.id,
      'name': special.name,
      'sort_order': special.sortOrder,
      'archived': 0,
      'color_token': null,
      'group_id': special.defaultGroupId,
      'conscious_spending_area':
          special.defaultConsciousSpendingArea?.storageValue,
    });
  }
  _log.log(
    'Seeded ${spendDefaults.length + SpecialCategory.values.length} '
    'default categories',
  );
}
