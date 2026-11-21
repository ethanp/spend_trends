import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/ui/banks/bank_name_rename_field.dart';
import 'package:spend_trends/ui/theme/finance_colors.dart';

const _iphoneStripSize = Size(390, 120);

void main() {
  setUpAll(() async {
    await ETheme.loadFontsForWidgetTests();
  });

  testWidgets('renaming a long bank name on iPhone', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(_iphoneStripSize);
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: ETheme.material3Dark,
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BankNameRenameField(
                    displayName: 'Charles Schwab Bank Investor Checking With A Long Name',
                    hintText: 'Bank name',
                    nameStyle: EText.body.large.copyWith(
                      fontWeight: FontWeight.w600,
                      color: FinanceColors.accentPrimary,
                    ),
                    accentColor: FinanceColors.accentPrimary,
                    onRenameConfirmed: (_) async {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.textContaining('Charles Schwab'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/bank_name_rename_field_editing.png'),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
