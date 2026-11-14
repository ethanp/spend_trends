import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/ui/banks/bank_name_rename_field.dart';

void main() {
  late List<String> confirmedNames;

  setUp(() => confirmedNames = []);

  Future<void> pumpRenameField(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              BankNameRenameField(
                displayName: 'Schwab checking',
                hintText: 'Checking',
                nameStyle: const TextStyle(fontSize: 14),
                accentColor: Colors.blue,
                onRenameConfirmed: (typedName) async =>
                    confirmedNames.add(typedName),
              ),
              const Text('elsewhere'),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Schwab checking'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bills');
    await tester.pump();
  }

  testWidgets('a long name keeps save and cancel on a phone-width screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const longBankName =
        'Charles Schwab Bank Investor Checking Account With A Very Long Name';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BankNameRenameField(
                  displayName: longBankName,
                  hintText: 'Bank name',
                  nameStyle: const TextStyle(fontSize: 17),
                  accentColor: Colors.blue,
                  onRenameConfirmed: (typedName) async =>
                      confirmedNames.add(typedName),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.textContaining('Charles Schwab'));
    await tester.pumpAndSettle();

    final Rect cancelRect = tester.getRect(find.byTooltip('Cancel rename'));
    final Rect saveRect = tester.getRect(find.byTooltip('Save name'));
    expect(cancelRect.right, lessThanOrEqualTo(375 - 16));
    expect(saveRect.right, lessThanOrEqualTo(cancelRect.left));

    await tester.tap(find.byTooltip('Cancel rename'));
    await tester.pumpAndSettle();
    expect(confirmedNames, isEmpty);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('cancel leaves edit mode without saving', (tester) async {
    await pumpRenameField(tester);

    await tester.tap(find.byTooltip('Cancel rename'));
    await tester.pumpAndSettle();

    expect(confirmedNames, isEmpty);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Schwab checking'), findsOneWidget);
  });

  testWidgets('Esc cancels without saving', (tester) async {
    await pumpRenameField(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(confirmedNames, isEmpty);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('save confirms the typed name once', (tester) async {
    await pumpRenameField(tester);

    await tester.tap(find.byTooltip('Save name'));
    await tester.pumpAndSettle();

    expect(confirmedNames, ['Bills']);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('clicking elsewhere on the Mac saves the typed name', (
    tester,
  ) async {
    await pumpRenameField(tester);

    await tester.tap(find.text('elsewhere'));
    await tester.pumpAndSettle();

    expect(confirmedNames, ['Bills']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
