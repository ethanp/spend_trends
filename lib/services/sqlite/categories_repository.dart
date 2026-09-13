import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/category_group.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';

class CategoriesRepository(final PowerSyncDatabase _powerSync) {
  final _uuid = const Uuid();

  Future<List<SpendCategory>> listActive() async {
    final rows = await _powerSync.getAll('''
      SELECT * FROM categories
      WHERE archived = 0
      ORDER BY sort_order ASC, name COLLATE NOCASE
      ''');
    return rows.map(_categoryFromRow).toList();
  }

  Future<List<SpendCategory>> listAll() async {
    final rows = await _powerSync.getAll(
      'SELECT * FROM categories ORDER BY sort_order ASC',
    );
    return rows.map(_categoryFromRow).toList();
  }

  Future<List<CategoryGroup>> listGroups() async {
    final rows = await _powerSync.getAll('''
      SELECT * FROM category_groups
      ORDER BY sort_order ASC, name COLLATE NOCASE
      ''');
    return rows.map(_groupFromRow).toList();
  }

  Future<void> upsertCategory(SpendCategory category) async {
    await _powerSync.upsert('categories', {
      'id': category.id,
      'name': category.name,
      'sort_order': category.sortOrder,
      'archived': category.archived ? 1 : 0,
      'color_token': category.colorToken,
      'group_id': category.groupId,
    });
  }

  Future<void> upsertGroup(CategoryGroup group) async {
    await _powerSync.upsert('category_groups', {
      'id': group.id,
      'name': group.name,
      'sort_order': group.sortOrder,
    });
  }

  Future<SpendCategory> createCategory({required String name}) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Category name is required.');
    }
    if (SpecialCategory.isReservedName(trimmedName)) {
      throw ArgumentError(
        '"$trimmedName" is a built-in category and cannot be recreated.',
      );
    }
    final active = await listActive();
    var nextSortOrder = 0;
    for (final category in active) {
      if (category.sortOrder >= nextSortOrder) {
        nextSortOrder = category.sortOrder + 1;
      }
    }
    final category = SpendCategory(
      id: _uuid.v4(),
      name: trimmedName,
      sortOrder: nextSortOrder,
      archived: false,
    );
    await upsertCategory(category);
    return category;
  }

  Future<CategoryGroup> createGroup({required String name}) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Group name is required.');
    }
    final groups = await listGroups();
    var nextSortOrder = 0;
    for (final group in groups) {
      if (group.sortOrder >= nextSortOrder) {
        nextSortOrder = group.sortOrder + 1;
      }
    }
    final group = CategoryGroup(
      id: _uuid.v4(),
      name: trimmedName,
      sortOrder: nextSortOrder,
    );
    await upsertGroup(group);
    return group;
  }

  Future<void> renameCategory({
    required String categoryId,
    required String name,
  }) async {
    if (categoryId == SpecialCategory.income.id ||
        categoryId == SpecialCategory.transfer.id) {
      throw StateError('Built-in categories cannot be renamed.');
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Category name is required.');
    }
    final reservedId = SpecialCategory.idForReservedName(trimmedName);
    if (reservedId != null && reservedId != categoryId) {
      throw ArgumentError(
        '"$trimmedName" is reserved for a built-in category.',
      );
    }
    final existing = await _requireCategory(categoryId);
    await upsertCategory(existing.copyWith(name: trimmedName));
  }

  Future<void> renameGroup({
    required String groupId,
    required String name,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Group name is required.');
    }
    final existing = await _requireGroup(groupId);
    await upsertGroup(
      CategoryGroup(
        id: existing.id,
        name: trimmedName,
        sortOrder: existing.sortOrder,
      ),
    );
  }

  Future<void> setCategoryGroup({
    required String categoryId,
    String? groupId,
  }) async {
    if (groupId != null) {
      await _requireGroup(groupId);
    }
    final existing = await _requireCategory(categoryId);
    await upsertCategory(
      existing.copyWith(groupId: groupId, clearGroupId: groupId == null),
    );
  }

  /// Deletes the group and clears membership on its categories.
  Future<void> deleteGroup(String groupId) async {
    if (SpecialCategory.isIncomeGroupId(groupId)) {
      throw StateError('The Income group cannot be deleted.');
    }
    await _requireGroup(groupId);
    await _powerSync.execute(
      'UPDATE categories SET group_id = NULL WHERE group_id = ?',
      [groupId],
    );
    await _powerSync.execute('DELETE FROM category_groups WHERE id = ?', [
      groupId,
    ]);
  }

  /// Move all spend/rules from [fromCategoryId] into [intoCategoryId],
  /// then hard-delete the source category. Use when retiring a duplicate
  /// (e.g. "Dining" → "Restaurants").
  Future<void> mergeCategoryInto({
    required String fromCategoryId,
    required String intoCategoryId,
  }) async {
    if (fromCategoryId == intoCategoryId) {
      throw ArgumentError('Cannot merge a category into itself.');
    }
    if (SpecialCategory.isSpecialId(fromCategoryId)) {
      throw StateError('Built-in categories cannot be merged away.');
    }
    await _ensureCategoriesExist(fromCategoryId, intoCategoryId);
    await _moveTransactionsAndRules(
      fromCategoryId: fromCategoryId,
      intoCategoryId: intoCategoryId,
    );
    await _powerSync.execute('DELETE FROM categories WHERE id = ?', [
      fromCategoryId,
    ]);
  }

  Future<void> _ensureCategoriesExist(
    String fromCategoryId,
    String intoCategoryId,
  ) async {
    final fromRow = await _powerSync.getOptional(
      'SELECT id FROM categories WHERE id = ? LIMIT 1',
      [fromCategoryId],
    );
    final intoRow = await _powerSync.getOptional(
      'SELECT id FROM categories WHERE id = ? LIMIT 1',
      [intoCategoryId],
    );
    if (fromRow == null || intoRow == null) {
      throw StateError('Both categories must exist to merge.');
    }
  }

  Future<void> _moveTransactionsAndRules({
    required String fromCategoryId,
    required String intoCategoryId,
  }) async {
    await _powerSync.execute(
      'UPDATE transactions SET user_category_id = ? WHERE user_category_id = ?',
      [intoCategoryId, fromCategoryId],
    );
    await _powerSync.execute(
      '''
      UPDATE transactions
      SET suggested_category_id = ?
      WHERE suggested_category_id = ?
      ''',
      [intoCategoryId, fromCategoryId],
    );
    await _powerSync.execute(
      'UPDATE categorization_rules SET category_id = ? WHERE category_id = ?',
      [intoCategoryId, fromCategoryId],
    );
  }

  Future<List<CategorizationRule>> listRules() async {
    final rows = await _powerSync.getAll(
      'SELECT * FROM categorization_rules ORDER BY priority DESC, pattern',
    );
    return rows.map(_ruleFromRow).toList();
  }

  Future<void> upsertRule(CategorizationRule rule) async {
    await _powerSync.upsert('categorization_rules', {
      'id': rule.id,
      'match_type': rule.matchType.storageValue,
      'pattern': rule.pattern,
      'category_id': rule.categoryId,
      'priority': rule.priority,
    });
  }

  Future<void> deleteRule(String ruleId) async {
    await _powerSync.execute('DELETE FROM categorization_rules WHERE id = ?', [
      ruleId,
    ]);
  }

  Future<SpendCategory> _requireCategory(String categoryId) async {
    final row = await _powerSync.getOptional(
      'SELECT * FROM categories WHERE id = ? LIMIT 1',
      [categoryId],
    );
    if (row == null) {
      throw StateError('Category not found.');
    }
    return _categoryFromRow(row);
  }

  Future<CategoryGroup> _requireGroup(String groupId) async {
    final row = await _powerSync.getOptional(
      'SELECT * FROM category_groups WHERE id = ? LIMIT 1',
      [groupId],
    );
    if (row == null) {
      throw StateError('Group not found.');
    }
    return _groupFromRow(row);
  }

  static SpendCategory _categoryFromRow(dynamic row) {
    final columns = (row as Map).cast<String, Object?>();
    return SpendCategory(
      id: columns['id'] as String,
      name: columns['name'] as String,
      sortOrder: columns['sort_order'].asInt(),
      archived: columns['archived'].asInt() == 1,
      colorToken: columns['color_token'] as String?,
      groupId: columns['group_id'] as String?,
    );
  }

  static CategoryGroup _groupFromRow(dynamic row) {
    final columns = (row as Map).cast<String, Object?>();
    return CategoryGroup(
      id: columns['id'] as String,
      name: columns['name'] as String,
      sortOrder: columns['sort_order'].asInt(),
    );
  }

  static CategorizationRule _ruleFromRow(dynamic row) {
    final columns = (row as Map).cast<String, Object?>();
    return CategorizationRule(
      id: columns['id'] as String,
      matchType: RuleMatchType.fromStorage(columns['match_type'] as String),
      pattern: columns['pattern'] as String,
      categoryId: columns['category_id'] as String,
      priority: columns['priority'].asInt(),
    );
  }
}

final categoriesRepositoryProvider = FutureProvider<CategoriesRepository>((
  ref,
) async {
  final database = await ref.watch(powerSyncDatabaseProvider.future);
  return CategoriesRepository(database);
});
