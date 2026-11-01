import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/remove_copilot_duplicates.dart';
import 'package:spend_trends/features/categories/categories_providers.dart';
import 'package:spend_trends/features/settings/settings_action_row.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/csv/import_copilot_transactions_csv.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';

import 'remove_copilot_duplicates_provider.dart';

class const CopilotImportTile() extends ConsumerStatefulWidget {
  @override
  ConsumerState<CopilotImportTile> createState() => _CopilotImportTileState();
}

class _CopilotImportTileState() extends ConsumerState<CopilotImportTile> {
  bool _busy = false;
  String? _message;
  CopilotImportProgress? _progress;
  CopilotImportCancellation? _cancellation;

  @override
  Widget build(BuildContext context) {
    return SettingsActionRow(
      icon: Icons.download,
      title: 'Import Copilot CSV',
      caption: 'Load your Copilot export, skipping repeats',
      onActivated: _importLocal,
      onCancel: _cancelImport,
      style: SettingsSectionStyle.copilotMigration,
      busy: _busy,
      message: _message ?? _progressLabel,
      progressFraction: _progress?.fraction,
    );
  }

  String? get _progressLabel {
    final CopilotImportProgress? progress = _progress;
    if (progress == null) return null;
    if (progress.total <= 0) return 'Starting…';
    return 'Imported ${progress.completed} / ${progress.total}';
  }

  void _cancelImport() {
    _cancellation?.cancel();
    if (!mounted) return;
    setState(() => _message = 'Cancelling…');
  }

  Future<void> _importLocal() async {
    final cancellation = CopilotImportCancellation();
    setState(() {
      _busy = true;
      _message = null;
      _progress = const CopilotImportProgress(completed: 0, total: 0);
      _cancellation = cancellation;
    });
    try {
      final result = await _importCsvWithProgress(cancellation);
      if (result.cancelled) {
        if (!mounted) return;
        setState(() {
          _message =
              'Cancelled after ${result.transactionCount} new'
              '${result.alreadyPresentCount > 0 ? ', ${result.alreadyPresentCount} already present' : ''}.';
        });
        if (result.transactionCount > 0) {
          ref.read(spendDataChangedProvider.notifier).notify();
        }
        return;
      }

      RemoveCopilotDuplicatesResult? dedupe;
      if (result.transactionCount > 0) {
        if (mounted) {
          setState(() => _message = 'Removing Copilot duplicates…');
        }
        final remover = await ref.read(removeCopilotDuplicatesProvider.future);
        dedupe = await remover.run();
      }
      if (mounted) {
        setState(() => _message = 'Applying categorization rules…');
      }
      final categorizer = await ref.read(categorizerProvider.future);
      await categorizer.recategorizeAll();
      ref.read(spendDataChangedProvider.notifier).notify();
      if (!mounted) return;
      setState(() {
        _message = _resultMessage(
          result,
          dedupe ??
              const RemoveCopilotDuplicatesResult(
                deletedCopilotCount: 0,
                linkedAccountMasks: 0,
              ),
        );
      });
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _cancellation = null;
        });
      }
    }
  }

  String _resultMessage(
    CopilotImportResult result,
    RemoveCopilotDuplicatesResult dedupe,
  ) {
    final parts = <String>[
      'Imported ${result.transactionCount} new across '
          '${result.accountCount} accounts',
    ];
    if (result.alreadyPresentCount > 0) {
      parts.add('${result.alreadyPresentCount} already present');
    }
    if (result.simplefinMatchSkipCount > 0) {
      parts.add('${result.simplefinMatchSkipCount} SimpleFIN matches');
    }
    if (result.notesFilledCount > 0) {
      parts.add('${result.notesFilledCount} notes filled');
    }
    if (dedupe.deletedCopilotCount > 0) {
      parts.add('removed ${dedupe.deletedCopilotCount} Copilot duplicates');
    }
    if (dedupe.deletedSameAccountCount > 0) {
      parts.add(
        'removed ${dedupe.deletedSameAccountCount} same-account duplicates',
      );
    }
    if (result.skippedRows > 0) {
      parts.add('${result.skippedRows} invalid');
    }
    return '${parts.join(', ')}.';
  }

  Future<CopilotImportResult> _importCsvWithProgress(
    CopilotImportCancellation cancellation,
  ) async {
    final importer = ImportCopilotTransactionsCsv(
      accountsRepository: await ref.read(accountsRepositoryProvider.future),
      transactionsRepository: await ref.read(
        transactionsRepositoryProvider.future,
      ),
    );
    return importer.importLocalFile(
      cancellation: cancellation,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() => _progress = progress);
      },
    );
  }
}
