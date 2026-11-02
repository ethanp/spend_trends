import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/use_cases/categories/categorizer.dart';
import 'package:spend_trends/domain/categories/category.dart';
import 'package:spend_trends/domain/categories/category_group.dart';
import 'package:spend_trends/domain/categories/rule_change_plan.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';
import 'package:spend_trends/ui/activity/activity_column_widths.dart';
import 'package:spend_trends/ui/activity/activity_transaction_tile.dart';
import 'package:spend_trends/ui/activity/manage_rule_sheet.dart';
import 'package:spend_trends/ui/activity/recategorize_form.dart';
import 'package:spend_trends/ui/activity/rule_impact_confirm_sheet.dart';
import 'package:spend_trends/data/repositories/accounts_repository.dart';
import 'package:spend_trends/data/repositories/categories_repository.dart';
import 'package:spend_trends/data/repositories/transactions_repository.dart';
import 'package:spend_trends/ui/widgets/category_picker.dart';
import 'package:spend_trends/ui/widgets/exclude_from_lifestyle_costs_switch.dart';

class _RecordingCategorizer() implements Categorizer {
  final List<RuleDraft> appliedDrafts = [];

  @override
  Future<RuleChangePlan> applyRuleChanges({
    List<RuleDraft> drafts = const [],
    Set<String> deletedRuleIds = const {},
  }) async {
    appliedDrafts.addAll(drafts);
    return RuleChangePlan(rulesBefore: const [], transactions: const []);
  }

  @override
  Future<List<BankTransaction>> transactionsClaimedBy(RuleDraft draft) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoTransactionsRepository() implements TransactionsRepository {
  @override
  Future<List<BankTransaction>> listCategorizedByRule(String ruleId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _groceries = SpendCategory(
  id: 'groceries',
  name: 'Groceries',
  sortOrder: 0,
  archived: false,
);

final _krogerTransaction = BankTransaction(
  id: 't1',
  accountId: 'checking',
  externalId: 'e1',
  postedAtMillis: DateTime(2026, 10, 3).millisecondsSinceEpoch,
  amountCents: -4200,
  rawDescription: 'KROGER #123',
  normalizedMerchant: 'KROGER',
  pending: false,
);

Widget _harness({
  required _RecordingCategorizer categorizer,
  required List<CategorizationRule> rules,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      categorizerProvider.overrideWith((ref) async => categorizer),
      categoriesListProvider.overrideWith((ref) async => const [_groceries]),
      categoryGroupsProvider.overrideWith(
        (ref) async => const <CategoryGroup>[],
      ),
      categorizationRulesProvider.overrideWith((ref) async => rules),
      accountsMapProvider.overrideWith((ref) async => const {}),
      transactionsRepositoryProvider.overrideWith(
        (ref) async => _NoTransactionsRepository(),
      ),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Finder get _lifestyleCostsSwitch => find.descendant(
  of: find.byType(ExcludeFromLifestyleCostsSwitch),
  matching: find.byType(Switch),
);

Finder get _groceriesInCategoryPicker => find.descendant(
  of: find.byType(CategoryPicker),
  matching: find.text('Groceries'),
);

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1000, 2400);
    view.devicePixelRatio = 1;
    addTearDown(view.reset);
  });

  testWidgets('categorizing with Exclude from lifestyle costs on saves the '
      'rule excluded', (tester) async {
    final categorizer = _RecordingCategorizer();
    String? completedCategoryId;
    await tester.pumpWidget(
      _harness(
        categorizer: categorizer,
        rules: const [],
        child: RecategorizeForm(
          transaction: _krogerTransaction,
          onCompleted: (categoryId) => completedCategoryId = categoryId,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(_lifestyleCostsSwitch).value, isFalse);
    await tester.tap(_lifestyleCostsSwitch);
    await tester.pumpAndSettle();
    await tester.tap(_groceriesInCategoryPicker);
    await tester.pumpAndSettle();

    final RuleDraft savedDraft = categorizer.appliedDrafts.single;
    expect(savedDraft.categoryId, 'groceries');
    expect(savedDraft.excludesFromLifestyleCosts, isTrue);
    expect(completedCategoryId, 'groceries');
  });

  testWidgets('Exclude from lifestyle costs starts from the rule the pattern '
      'updates and keeps it when untouched', (tester) async {
    final categorizer = _RecordingCategorizer();
    await tester.pumpWidget(
      _harness(
        categorizer: categorizer,
        rules: const [
          CategorizationRule(
            id: 'kroger',
            matchType: RuleMatchType.merchantContains,
            pattern: 'kroger',
            categoryId: 'groceries',
            excludesFromLifestyleCosts: true,
          ),
        ],
        child: RecategorizeForm(
          transaction: _krogerTransaction,
          onCompleted: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(_lifestyleCostsSwitch).value, isTrue);
    await tester.tap(_groceriesInCategoryPicker);
    await tester.pumpAndSettle();

    expect(categorizer.appliedDrafts.single.excludesFromLifestyleCosts, isNull);
  });

  testWidgets('Manage rule switch saves the exclusion on the same rule', (
    tester,
  ) async {
    final categorizer = _RecordingCategorizer();
    const rule = CategorizationRule(
      id: 'kroger',
      matchType: RuleMatchType.merchantContains,
      pattern: 'kroger',
      categoryId: 'groceries',
    );
    await tester.pumpWidget(
      _harness(
        categorizer: categorizer,
        rules: const [rule],
        child: const ManageRuleSheet(rule: rule),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_lifestyleCostsSwitch);
    await tester.pumpAndSettle();

    final RuleDraft savedDraft = categorizer.appliedDrafts.single;
    expect(savedDraft.sameMatchAs(rule), isTrue);
    expect(savedDraft.categoryId, 'groceries');
    expect(savedDraft.excludesFromLifestyleCosts, isTrue);
    expect(tester.widget<Switch>(_lifestyleCostsSwitch).value, isTrue);
  });

  test('a confirmed suggestion group carries its exclusion into the draft', () {
    const group = RuleImpactGroup(
      pattern: 'kroger',
      categoryId: 'groceries',
      categoryName: 'Groceries',
      transactions: [],
    );

    expect(group.ruleDraft.excludesFromLifestyleCosts, isNull);
    expect(
      group
          .copyWith(excludesFromLifestyleCosts: true)
          .ruleDraft
          .excludesFromLifestyleCosts,
      isTrue,
    );
  });

  testWidgets('Activity row marks a transaction excluded from lifestyle '
      'costs', (tester) async {
    final excludedTransaction = BankTransaction(
      id: 't2',
      accountId: 'checking',
      externalId: 'e2',
      postedAtMillis: DateTime(2026, 10, 4).millisecondsSinceEpoch,
      amountCents: -90000,
      rawDescription: 'CLOSING COSTS',
      normalizedMerchant: 'CLOSING COSTS',
      pending: false,
      categoryId: 'groceries',
      excludedFromLifestyleCosts: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivityTransactionTile(
            transaction: excludedTransaction,
            account: null,
            category: _groceries,
            onActivated: () {},
            columnWidths: const ActivityColumnWidths(
              category: 120,
              account: 120,
              title: 300,
              amount: 100,
            ),
          ),
        ),
      ),
    );

    expect(find.text('excluded'), findsOneWidget);
  });
}
