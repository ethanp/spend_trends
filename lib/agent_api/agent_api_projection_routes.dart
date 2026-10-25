import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:spend_trends/agent_api/agent_api_json.dart';
import 'package:spend_trends/agent_api/live_retirement_projection.dart';
import 'package:spend_trends/domain/account_tax_treatment.dart';
import 'package:spend_trends/features/projections/projections_providers.dart';

/// The Projections tab's retirement projection, and its assumptions.
class const AgentApiProjectionRoutes({
  required final ProviderContainer container,
}) {
  void mount(Router router) {
    router
      ..get('/projections', _projection)
      ..patch('/projections/assumptions', _updateAssumptions);
  }

  /// What the tab shows: live starting point, assumptions, earliest
  /// retirement age, and every year (today's dollars).
  Future<Response> _projection(Request request) async {
    final projection = await LiveRetirementProjection(container: container)
        .load();
    final start = projection.start;
    return jsonOk({
      'basis':
          'Today’s dollars (real returns). Live balances and the last 365 '
          'days of take-home, non-housing spending, and 401(k) payroll '
          'contributions. Life events apply from the first year they cover '
          'at mid-year: a job sets take-home, a home sets mortgage terms and '
          'carrying costs (moving sells the previous home), and each child '
          'adds its yearly cost.',
      'currentAge': projection.currentAge,
      'earliestRetirementAge': projection.earliestRetirementAge,
      'savingsTarget': switch (projection.savingsTarget) {
        null => null,
        final target => {
          'retirementAge': target.retirementAge,
          'maxNonHousingSpendingAnnual': target.maxNonHousingSpendingAnnual
              .round(),
          'requiredInvestingAnnual': target.requiredInvestingAnnual.round(),
          'requiredInvestingPercent': target.requiredInvestingPercent,
        },
      },
      'assumptions': projection.assumptions.toJson(),
      'startingPoint': {
        'takeHomeAnnual': start.takeHomeAnnual.round(),
        'nonHousingSpendingAnnual': start.nonHousingSpendingAnnual.round(),
        'payrollContributionsAnnual': start.payrollContributionsAnnual.round(),
        'mortgageBalance': start.mortgageBalance.round(),
        'homeValue': start.homeValue.round(),
        'balances': {
          for (final treatment in AccountTaxTreatment.values)
            treatment.name: start.balanceFor(treatment).round(),
        },
        'taxTreatmentByAccountId': {
          for (final entry in start.treatmentByAccountId.entries)
            entry.key: entry.value.name,
        },
      },
      'years': [
        for (final year in projection.years)
          {
            'age': year.age,
            'year': year.year,
            'taxable': year.taxable.round(),
            'traditional': year.traditional.round(),
            'roth': year.roth.round(),
            'college': year.college.round(),
            'liquid': year.liquid.round(),
            'homeEquity': year.homeEquity.round(),
            'income': year.income.round(),
            'spending': year.spending.round(),
            'housing': year.housing.round(),
            'mortgagePayment': year.mortgagePayment.round(),
          },
      ],
    });
  }

  /// Body: any assumption keys from `GET /projections` → `assumptions`;
  /// `null` clears birthDate or an override.
  Future<Response> _updateAssumptions(Request request) async {
    final changes = await request.readJsonObject();
    final updated = await container
        .read(projectionAssumptionsEditorProvider)
        .apply(changes);
    return jsonOk({'assumptions': updated.toJson()});
  }
}
