import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/transactions/transaction.dart';
import 'package:spend_trends/ui/activity/recategorize_form.dart';
import 'package:spend_trends/ui/widgets/app_sheet_panel.dart';

/// Modal wrapper around [RecategorizeForm] for narrow / non-split layouts.
class const RecategorizeSheet({required final BankTransaction transaction})
    extends StatelessWidget {
  /// Returns the assigned category id, or null if dismissed / note-only save.
  static Future<String?> show(
    BuildContext context, {
    required WidgetRef ref,
    required BankTransaction transaction,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => RecategorizeSheet(transaction: transaction),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetPanel(
      child: RecategorizeForm(
        transaction: transaction,
        onCompleted: (categoryId) => Navigator.of(context).pop(categoryId),
      ),
    );
  }
}
