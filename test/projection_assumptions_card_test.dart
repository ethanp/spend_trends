import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/domain/account_tax_treatment.dart';
import 'package:spend_trends/domain/projection/life_plan.dart';
import 'package:spend_trends/domain/projection/projection_assumptions.dart';
import 'package:spend_trends/domain/projection/projection_starting_point.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/features/projections/projection_assumptions_card.dart';
import 'package:spend_trends/features/projections/projections_providers.dart';

void main() {
  final projection = RetirementProjection(
    lifePlan: LifePlan(const []),
    assumptions: ProjectionAssumptions(birthDate: DateTime(1990, 11, 22)),
    start: ProjectionStartingPoint(
      today: DateTime(2026, 10, 25),
      balanceByTreatment: const {AccountTaxTreatment.taxable: 1400000},
      treatmentByAccountId: const {},
      homeValue: 560000,
      mortgageBalance: 0,
      takeHomeAnnual: 199000,
      nonHousingSpendingAnnual: 76500,
      payrollContributionsAnnual: 25000,
    ),
  );

  testWidgets('assumption sliders lay out with their sweep lines', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          retirementProjectionProvider.overrideWith((ref) async => projection),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 520,
                child: ProjectionAssumptionsCard(projection: projection),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsNWidgets(7));
    expect(find.text('last 365 days'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^invest \d+%$')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('saving an assumption keeps the last projection on screen', () async {
    final container = ProviderContainer(
      overrides: [
        retirementProjectionProvider.overrideWith((ref) async => projection),
      ],
    );
    addTearDown(container.dispose);
    container.listen(draftedRetirementProjectionProvider, (_, _) {});
    await container.read(retirementProjectionProvider.future);

    container.invalidate(retirementProjectionProvider);

    final AsyncValue<RetirementProjection> shown = container.read(
      draftedRetirementProjectionProvider,
    );
    expect(shown.isLoading, isFalse);
    expect(shown.value, same(projection));
  });
}
