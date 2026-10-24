import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/activity/recategorize_form.dart';

/// Banks right pane while reviewing a transaction from a pull.
class const BanksPullReviewPane({
  required final BankTransaction transaction,
  required final VoidCallback onCategorized,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              ELayout.spaceLg,
              ELayout.spaceLg,
              ELayout.spaceLg,
              ELayout.spaceSm,
            ),
            child: KeyedSubtree(
              key: ValueKey(transaction.id),
              child: RecategorizeForm(
                transaction: transaction,
                onCompleted: (categoryId) {
                  if (categoryId != null) onCategorized();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
