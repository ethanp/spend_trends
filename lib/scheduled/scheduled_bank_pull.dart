import 'dart:async';
import 'dart:io';

import 'package:ethan_sync/ethan_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:spend_trends/data/sync/sync_config.dart';
import 'package:spend_trends/use_cases/simplefin_pull/pull_simplefin_transactions.dart';

/// The Banks tab's "Pull bank transactions", run unattended on the home
/// server as its own PowerSync client.
///
/// It downloads first so the pull sees the same last successful pull as the
/// Mac and phone, and exits only once every row it wrote is uploaded through
/// PostgREST, the same path the apps upload through.
class ScheduledBankPull._() {
  static const _syncTimeout = Duration(minutes: 10);

  static Future<void> run({required String databasePath}) async {
    final container = ProviderContainer(
      overrides: [
        syncConfigProvider.overrideWithValue(
          buildSpendTrendsSyncConfig(
            databasePath: () async => databasePath,
            connection: const ConnectionSettings.oneShotRun(),
          ),
        ),
      ],
      // A failed open or connect must fail the run; retries never complete.
      retry: (retryCount, error) => null,
    );
    try {
      stdout.writeln('Connecting to PowerSync');
      final connectStartedAt = DateTime.now();
      await SyncLifecycle.start(container, followAppForeground: false);
      final PowerSyncDatabase database = await container.read(
        powerSyncDatabaseProvider.future,
      );
      await _waitForDownloadSince(database, connectStartedAt);
      stdout.writeln('Downloaded from PowerSync; pulling banks');

      final PullSimpleFinTransactions puller = await container.read(
        pullSimpleFinTransactionsProvider.future,
      );
      final result = await puller.pull();
      stdout.writeln(
        'Pulled ${result.accountCount} accounts, '
        '${result.transactionCount} transactions, '
        '${result.errors.length} bridge errors',
      );
      for (final bridgeError in result.errors) {
        stdout.writeln('  ${bridgeError.code}: ${bridgeError.message}');
      }

      await _waitUntilUploadQueueEmpty(database);
      stdout.writeln('Uploaded every change');
    } finally {
      container.dispose();
    }
  }

  /// PowerSync records `lastSyncedAt` in whole seconds, so a catch-up that
  /// finishes in the same second as the connect reads as that second's start.
  static Future<void> _waitForDownloadSince(
    PowerSyncDatabase database,
    DateTime connectStartedAt,
  ) async {
    final connectStartedSecond = DateTime.fromMillisecondsSinceEpoch(
      connectStartedAt.millisecondsSinceEpoch ~/ 1000 * 1000,
    );
    bool downloadedSinceConnect(SyncStatus status) =>
        status.connected &&
        !status.downloading &&
        !(status.lastSyncedAt?.isBefore(connectStartedSecond) ?? true);

    if (downloadedSinceConnect(database.currentStatus)) return;
    await database.statusStream
        .map((status) {
          stdout.writeln(
            '  PowerSync connected=${status.connected} '
            'downloading=${status.downloading} '
            'lastSyncedAt=${status.lastSyncedAt?.toIso8601String()}',
          );
          return status;
        })
        .firstWhere(downloadedSinceConnect)
        .timeout(
          _syncTimeout,
          onTimeout: () => throw TimeoutException(
            'No PowerSync download within $_syncTimeout: '
            '${database.currentStatus}',
          ),
        );
  }

  static Future<void> _waitUntilUploadQueueEmpty(
    PowerSyncDatabase database,
  ) async {
    await database
        .watch('SELECT COUNT(*) AS pending FROM ps_crud')
        .firstWhere((pendingRows) => pendingRows.first['pending'] == 0)
        .timeout(
          _syncTimeout,
          onTimeout: () => throw TimeoutException(
            'Upload queue not empty after $_syncTimeout: '
            '${database.currentStatus.uploadError}',
          ),
        );
  }
}
