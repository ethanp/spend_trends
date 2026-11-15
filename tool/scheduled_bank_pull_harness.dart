@Timeout(Duration(minutes: 30))
library;

import 'dart:io';

import 'package:ethan_sync/ethan_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spend_trends/scheduled/scheduled_bank_pull.dart';

/// Scheduled bank pull on the home server: Flutter test binding without a
/// window, like the workbench daemon. Not under test/ so `flutter test` does
/// not run it with the suite. See `scheduled_bank_pull/README.md`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _IoHttpOverrides();

  test('pulls banks and uploads every change', () async {
    final databasePath = Platform.environment['BANK_PULL_DATABASE_PATH'];
    if (databasePath == null || databasePath.isEmpty) {
      throw StateError('Set BANK_PULL_DATABASE_PATH');
    }
    await DotEnvSyncBootstrap.loadEnv();
    await ScheduledBankPull.run(databasePath: databasePath);
  });
}

/// TestWidgetsFlutterBinding otherwise stubs HTTP as 400.
class _IoHttpOverrides() extends HttpOverrides;
