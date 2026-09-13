import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';

import 'banks_pull_live_session.dart';

/// Time window for transactions first imported during one SimpleFIN pull.
class const PullImportWindow({
  required final DateTime startedAt,
  final DateTime? finishedAt,
}) {
  @override
  bool operator ==(Object other) =>
      other is PullImportWindow &&
      other.startedAt == startedAt &&
      other.finishedAt == finishedAt;

  @override
  int get hashCode => Object.hash(startedAt, finishedAt);
}

final pullImportedTransactionsProvider =
    FutureProvider.family<List<BankTransaction>, PullImportWindow>((
      ref,
      window,
    ) async {
      ref.watch(spendDataChangedProvider);
      ref.watch(banksPullLiveSessionProvider);
      final repository = await ref.watch(transactionsRepositoryProvider.future);
      final end = window.finishedAt ?? DateTime.now().toUtc();
      return repository.listImportedBetween(window.startedAt, end);
    });
