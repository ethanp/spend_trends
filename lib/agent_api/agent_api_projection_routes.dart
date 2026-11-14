import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:spend_trends/agent_api/agent_api_json.dart';
import 'package:spend_trends/agent_api/live_retirement_projection.dart';
import 'package:spend_trends/domain/accounts/account_tax_treatment.dart';
import 'package:spend_trends/domain/projection/roth_conversion_comparison.dart';
import 'package:spend_trends/use_cases/projection/projection_assumptions_editor.dart';

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
          'days of take-home, non-housing spending, and payroll '
          'contributions (401(k), HSA). Life events apply from the first year they cover '
          'at mid-year: a job sets take-home, a home sets mortgage terms and '
          'carrying costs (moving sells the previous home), and each child '
          'adds its yearly cost. Taxes are 2026 federal brackets for '
          'filingStatus (no state tax): ordinary income after the standard '
          'deduction, long-term gains stacked in the 0/15/20% bands, the '
          'taxable part of Social Security, and a 10% penalty before 59½. '
          'Taxable tracks cost and Roth tracks contributions and '
          'conversions (conversions freely withdrawable five tax years '
          'later): each account’s recorded taxBasisCents (PATCH /accounts, '
          'or POST /imports/empower/tax-basis), cash at its balance, and '
          'taxableCostPercent / rothContributionsPercent of the rest. '
          'Inflation makes taxable gains. Working years tax draws on top of '
          'the wages behind take-home (payroll tax and 401(k) undone). '
          'Retired before 65 the household buys the age-rated benchmark '
          'marketplace plan (marketplacePremiumMonthlyDollars for one adult '
          'today) and gets the premium tax credit, none past 400% of the '
          'poverty line; taxes can be negative when the credit is larger. '
          'Conversions stop short of losing that credit. A year’s cash need and its '
          'taxes are drawn from taxable, then (before 59½) Roth '
          'contributions and seasoned conversions, then traditional, then '
          'Roth; from 59½ traditional then Roth. rothConversionBracketPercent '
          'fills ordinary income to that bracket’s top each retired year, '
          'converting what spending does not use. Required distributions '
          'start at 75. taxes is federal tax beyond what take-home already '
          'paid; income is take-home, or Social Security before tax.',
      'currentAge': projection.currentAge,
      'earliestRetirementAge': projection.earliestRetirementAge,
      'earliestRetirementYear': projection.earliestRetirementYear,
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
      'rothConversionComparison': RothConversionComparison(projection).outcomes
          .mapL(
            (outcome) => {
              'rothConversionBracketPercent': outcome.bracketPercent,
              'lifetimeTaxesPresentValue': outcome.lifetimeTaxesPresentValue
                  .round(),
              'leftToHeirsAtEndAge': outcome.leftToHeirs.round(),
              'earliestRetirementAge': outcome.earliestRetirementAge,
            },
          ),
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
        'recordedTaxBasis': {
          for (final treatment in AccountTaxTreatment.values)
            treatment.name: (start.taxBasisByTreatment[treatment] ?? 0).round(),
        },
        'balanceWithoutTaxBasis': {
          for (final treatment in AccountTaxTreatment.values)
            treatment.name: start.balanceWithoutTaxBasisFor(treatment).round(),
        },
        'taxTreatmentByAccountId': {
          for (final entry in start.treatmentByAccountId.entries)
            entry.key: entry.value.name,
        },
      },
      'years': projection.years.mapL(
        (year) => {
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
          'taxes': year.taxes.round(),
          'rothConversion': year.rothConversion.round(),
          'housing': year.housing.round(),
          'mortgagePayment': year.mortgagePayment.round(),
          'moveCosts': year.moveCosts.round(),
        },
      ),
    });
  }

  /// Body: any assumption keys from `GET /projections` → `assumptions`;
  /// `null` clears birthDate, an override, or the conversion bracket.
  Future<Response> _updateAssumptions(Request request) async {
    final changes = await request.readJsonObject();
    final updated = await container
        .read(projectionAssumptionsEditorProvider)
        .apply(changes);
    return jsonOk({'assumptions': updated.toJson()});
  }
}
