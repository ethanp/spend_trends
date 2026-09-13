import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/activity/recategorize_form.dart';

/// Banks right pane while reviewing a transaction from a pull.
class const BanksPullReviewPane({
  required final BankTransaction transaction,
  required final VoidCallback onCategorized,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(ELayout.spaceLg).withOverlaidTabBar(context),
      children: [
        Text('Review transaction', style: EText.section),
        const SizedBox(height: ELayout.spaceMd),
        KeyedSubtree(
          key: ValueKey(transaction.id),
          child: RecategorizeForm(
            transaction: transaction,
            onCompleted: (categoryId) {
              if (categoryId != null) onCategorized();
            },
          ),
        ),
      ],
    );
  }
}
