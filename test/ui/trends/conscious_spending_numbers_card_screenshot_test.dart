import 'dart:async';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spend_trends/domain/categories/conscious_spending_area.dart';
import 'package:spend_trends/domain/categories/conscious_spending_numbers.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/ui/projections/projections_providers.dart';
import 'package:spend_trends/ui/trends/conscious_spending_numbers_card.dart';

/// The card at an iPhone 14 Pro Max and at a quarter, half, and all of a
/// 3840 pt monitor. Goldens double as the screenshots to judge the layout by:
/// `flutter test --update-goldens test/ui/trends/conscious_spending_numbers_card_screenshot_test.dart`
class const _ScreenWidth({
  required final String name,
  required final double width,
  required final TargetPlatform platform,
  required final int expectedColumns,

  /// The phone's own text size setting, which [Text] applies on top.
  final double systemTextScale = 1.0,
});

const _screenWidths = [
  _ScreenWidth(
    name: 'iphone_14_pro_max',
    width: 430,
    platform: TargetPlatform.iOS,
    expectedColumns: 1,
    systemTextScale: 1.235,
  ),
  _ScreenWidth(
    name: 'macos_quarter_monitor',
    width: 960,
    platform: TargetPlatform.macOS,
    expectedColumns: 2,
  ),
  _ScreenWidth(
    name: 'macos_half_monitor',
    width: 1920,
    platform: TargetPlatform.macOS,
    expectedColumns: 3,
  ),
  _ScreenWidth(
    name: 'macos_full_monitor',
    width: 3840,
    platform: TargetPlatform.macOS,
    expectedColumns: 6,
  ),
];

void main() {
  setUpAll(ETheme.loadFontsForWidgetTests);

  for (final screenWidth in _screenWidths) {
    testWidgets('three numbers card at ${screenWidth.name}', (tester) async {
      debugDefaultTargetPlatformOverride = screenWidth.platform;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(Size(screenWidth.width, 1500));
      tester.platformDispatcher.textScaleFactorTestValue =
          screenWidth.systemTextScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      try {
        await tester.pumpWidget(_cardScreen(_fixtureNumbers()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final BuildContext tileContext = tester.element(
          find.textContaining('Fixed', findRichText: true).first,
        );
        expect(
          EBalancedRowsTileGrid.columnCountOf(tileContext),
          screenWidth.expectedColumns,
        );
        await expectLater(
          find.byType(ConsciousSpendingNumbersCard),
          matchesGoldenFile(
            'goldens/conscious_spending_numbers_card_${screenWidth.name}.png',
          ),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}

Widget _cardScreen(ConsciousSpendingNumbers numbers) {
  return ProviderScope(
    overrides: [
      retirementProjectionProvider.overrideWith(
        (ref) => Completer<RetirementProjection>().future,
      ),
    ],
    child: MaterialApp(
      theme: ETheme.material3Dark,
      debugShowCheckedModeBanner: false,
      home: Material(
        color: EColors.background,
        child: ListView(
          padding: const EdgeInsets.all(ELayout.spaceLg),
          children: [
            ConsciousSpendingNumbersCard(consciousSpendingNumbers: numbers),
          ],
        ),
      ),
    ),
  );
}

/// Five-digit months, an over-guideline fixed costs share, and a 6mo window
/// that drew cash down, so the widest figures and both colors show.
ConsciousSpendingNumbers _fixtureNumbers() {
  final DateTime lastDay = DateTime(2026, 11, 20);
  ConsciousSpendingWindowTotals totals(
    ConsciousSpendingWindow window, {
    required int annualPayDollars,
    required int fixedCostsDollars,
    required int investmentsDollars,
    required int guiltFreeDollars,
    required int excludedDollars,
  }) {
    int windowCents(int annualDollars) =>
        (annualDollars * 100 * window.days / 365).round();
    return ConsciousSpendingWindowTotals(
      window: window,
      firstDay: lastDay.subtract(Duration(days: window.days - 1)),
      lastDay: lastDay,
      takeHomeCents: windowCents(annualPayDollars - 23000),
      payrollContributionCents: windowCents(23000),
      centsByArea: {
        ConsciousSpendingArea.fixedCosts: windowCents(fixedCostsDollars),
        ConsciousSpendingArea.investments: windowCents(investmentsDollars),
        ConsciousSpendingArea.guiltFree: windowCents(guiltFreeDollars),
      },
      excludedFromLifestyleCents: windowCents(excludedDollars),
      mortgagePrincipalCents: windowCents(14000),
    );
  }

  return ConsciousSpendingNumbers(
    lastDay: lastDay,
    totalsByWindow: {
      ConsciousSpendingWindow.twoYears: totals(
        ConsciousSpendingWindow.twoYears,
        annualPayDollars: 214000,
        fixedCostsDollars: 101000,
        investmentsDollars: 52000,
        guiltFreeDollars: 38000,
        excludedDollars: 9000,
      ),
      ConsciousSpendingWindow.oneYear: totals(
        ConsciousSpendingWindow.oneYear,
        annualPayDollars: 226000,
        fixedCostsDollars: 118000,
        investmentsDollars: 57000,
        guiltFreeDollars: 41000,
        excludedDollars: 18000,
      ),
      ConsciousSpendingWindow.sixMonths: totals(
        ConsciousSpendingWindow.sixMonths,
        annualPayDollars: 231000,
        fixedCostsDollars: 139000,
        investmentsDollars: 61000,
        guiltFreeDollars: 44000,
        excludedDollars: 36000,
      ),
    },
  );
}
