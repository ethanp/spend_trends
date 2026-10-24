import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:spend_trends/agent_api/agent_api_json.dart';
import 'package:spend_trends/agent_api/categorization_snapshot.dart';
import 'package:spend_trends/agent_api/rule_change_request.dart';
import 'package:spend_trends/domain/rule_change_plan.dart';
import 'package:spend_trends/domain/categorizer.dart';
import 'package:spend_trends/domain/conscious_spending_area.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/categories_repository.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';

/// Categorization writes, each through the same repository / [Categorizer]
/// call the UI makes, then one spend-data refresh for open screens. Categories
/// change only through rules.
class const AgentApiWriteRoutes({required final ProviderContainer container}) {
  void mount(Router router) {
    router
      ..patch('/transactions/<transactionId>', _setNote)
      ..post('/rules', _applyRuleChanges)
      ..patch('/rules/<ruleId>', _updateRule)
      ..delete('/rules/<ruleId>', _deleteRule)
      ..post('/rules/recategorize-all', _recategorizeAll)
      ..post('/categories', _createCategory)
      ..patch('/categories/<categoryId>', _updateCategory)
      ..post('/categories/<categoryId>/merge', _mergeCategory)
      ..post('/groups', _createGroup);
  }

  Future<Response> _setNote(Request request, String transactionId) async {
    final body = await request.readJsonObject();
    final TransactionsRepository transactionsRepository = await container.read(
      transactionsRepositoryProvider.future,
    );
    await transactionsRepository.setNote(
      transactionId: transactionId,
      note: body['note'] as String?,
    );
    return _respondAfterWrite({'updated': 1});
  }

  /// Applies one rule or `{rules, deleteRuleIds}` (see [RuleChangeRequest])
  /// and reports what moved, same shape as `POST /rules/plan`.
  Future<Response> _applyRuleChanges(Request request) async {
    final snapshot = await CategorizationSnapshot.load(container);
    final ruleChanges = RuleChangeRequest.fromBody(
      await request.readJsonObject(),
      snapshot,
    );
    return _respondWithAppliedPlan(
      snapshot,
      drafts: ruleChanges.drafts,
      deletedRuleIds: ruleChanges.deletedRuleIds,
    );
  }

  /// Retargets and/or re-notes an existing rule.
  Future<Response> _updateRule(Request request, String ruleId) async {
    final body = await request.readJsonObject();
    final snapshot = await CategorizationSnapshot.load(container);
    final rule = snapshot.rulesById[ruleId];
    if (rule == null) return jsonError('No rule $ruleId', status: 404);
    final categoryId = body['categoryId'] as String? ?? rule.categoryId;
    if (!snapshot.categoriesById.containsKey(categoryId)) {
      throw ArgumentError('No category $categoryId.');
    }
    return _respondWithAppliedPlan(
      snapshot,
      drafts: [
        RuleDraft.retargeting(
          rule,
          categoryId: categoryId,
          note: body['note'] as String?,
        ),
      ],
    );
  }

  /// Deletes the rule; its transactions go to the next most specific
  /// matching rule, or become uncategorized.
  Future<Response> _deleteRule(Request request, String ruleId) async {
    final snapshot = await CategorizationSnapshot.load(container);
    if (!snapshot.rulesById.containsKey(ruleId)) {
      return jsonError('No rule $ruleId', status: 404);
    }
    return _respondWithAppliedPlan(snapshot, deletedRuleIds: {ruleId});
  }

  Future<Response> _recategorizeAll(Request request) async {
    final snapshot = await CategorizationSnapshot.load(container);
    final Categorizer categorizer = await container.read(
      categorizerProvider.future,
    );
    final plan = await categorizer.recategorizeAll();
    return _respondAfterWrite(
      RuleChangeReport(plan: plan, snapshot: snapshot).toJson(),
    );
  }

  Future<Response> _respondWithAppliedPlan(
    CategorizationSnapshot snapshot, {
    List<RuleDraft> drafts = const [],
    Set<String> deletedRuleIds = const {},
  }) async {
    final Categorizer categorizer = await container.read(
      categorizerProvider.future,
    );
    final plan = await categorizer.applyRuleChanges(
      drafts: drafts,
      deletedRuleIds: deletedRuleIds,
    );
    return _respondAfterWrite(
      RuleChangeReport(plan: plan, snapshot: snapshot).toJson(),
    );
  }

  Future<Response> _createCategory(Request request) async {
    final body = await request.readJsonObject();
    final CategoriesRepository categoriesRepository = await container.read(
      categoriesRepositoryProvider.future,
    );
    final category = await categoriesRepository.createCategory(
      name: body.requiredString('name'),
    );
    await _applyCategoryPlacement(categoriesRepository, category.id, body);
    return _respondAfterWrite({'id': category.id});
  }

  /// Only keys present in the body change; `null` clears group / area.
  Future<Response> _updateCategory(Request request, String categoryId) async {
    final body = await request.readJsonObject();
    final CategoriesRepository categoriesRepository = await container.read(
      categoriesRepositoryProvider.future,
    );
    if (body.containsKey('name')) {
      await categoriesRepository.renameCategory(
        categoryId: categoryId,
        name: body.requiredString('name'),
      );
    }
    await _applyCategoryPlacement(categoriesRepository, categoryId, body);
    return _respondAfterWrite({'id': categoryId});
  }

  Future<void> _applyCategoryPlacement(
    CategoriesRepository categoriesRepository,
    String categoryId,
    Map<String, dynamic> body,
  ) async {
    if (body.containsKey('groupId')) {
      await categoriesRepository.setCategoryGroup(
        categoryId: categoryId,
        groupId: body['groupId'] as String?,
      );
    }
    if (body.containsKey('consciousSpendingArea')) {
      final areaName = body['consciousSpendingArea'] as String?;
      final area = ConsciousSpendingArea.fromStorage(areaName);
      if (areaName != null && area == null) {
        throw ArgumentError('Unknown conscious spending area $areaName.');
      }
      await categoriesRepository.setConsciousSpendingArea(
        categoryId: categoryId,
        area: area,
      );
    }
  }

  Future<Response> _mergeCategory(Request request, String categoryId) async {
    final body = await request.readJsonObject();
    final CategoriesRepository categoriesRepository = await container.read(
      categoriesRepositoryProvider.future,
    );
    await categoriesRepository.mergeCategoryInto(
      fromCategoryId: categoryId,
      intoCategoryId: body.requiredString('intoCategoryId'),
    );
    return _respondAfterWrite({'mergedInto': body['intoCategoryId']});
  }

  Future<Response> _createGroup(Request request) async {
    final body = await request.readJsonObject();
    final CategoriesRepository categoriesRepository = await container.read(
      categoriesRepositoryProvider.future,
    );
    final group = await categoriesRepository.createGroup(
      name: body.requiredString('name'),
    );
    return _respondAfterWrite({'id': group.id});
  }

  Response _respondAfterWrite(Map<String, Object?> outcome) {
    container.read(spendDataChangedProvider.notifier).notify();
    return jsonOk(outcome);
  }
}
